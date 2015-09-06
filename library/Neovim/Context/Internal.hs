{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{- |
Module      :  Neovim.Context.Internal
Description :  Abstract description of the plugin provider's internal context
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental
Portability :  GHC

To shorten function and data type names, import this qualfied as @Internal@.
-}
module Neovim.Context.Internal
    where

import           Neovim.Plugin.Classes
import           Neovim.Plugin.IPC            (SomeMessage)

import           Control.Applicative
import           Control.Concurrent           (ThreadId, forkIO)
import           Control.Concurrent           (MVar, newEmptyMVar)
import           Control.Concurrent.STM
import           Control.Monad.Base
import           Control.Monad.Catch
import           Control.Monad.Except
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Resource
import qualified Data.ByteString.UTF8         as U (fromString)
import           Data.Data                    (Typeable)
import           Data.Map                     (Map)
import qualified Data.Map                     as Map
import           Data.MessagePack             (Object)
import           Data.String                  (IsString (..))
import           System.Log.Logger
import           Text.PrettyPrint.ANSI.Leijen hiding ((<$>))

import           Prelude


-- | This is the environment in which all plugins are initially started.
-- Stateless functions use '()' for the static configuration and the mutable
-- state and there is another type alias for that case: 'Neovim''.
--
-- Functions have to run in this transformer stack to communicate with neovim.
-- If parts of your own functions dont need to communicate with neovim, it is
-- good practice to factor them out. This allows you to write tests and spot
-- errors easier. Essentially, you should treat this similar to 'IO' in general
-- haskell programs.
newtype Neovim r st a = Neovim
    { unNeovim :: ResourceT (StateT st (ReaderT (Config r st) IO)) a }

  deriving (Functor, Applicative, Monad, MonadIO, MonadState st
           , MonadThrow, MonadCatch, MonadMask, MonadResource)


instance MonadBase IO (Neovim r st) where
    liftBase = liftIO


-- | User facing instance declaration for the reader state.
instance MonadReader r (Neovim r st) where
    ask = Neovim $ asks customConfig
    local f (Neovim a) = do
        r <- Neovim $ ask
        s <- get
        fmap fst . liftIO $ runReaderT (runStateT (runResourceT a) s)
                    (r { customConfig = f (customConfig r)})


-- | Same as 'ask' for the 'InternalConfig'.
ask' :: Neovim r st (Config r st)
ask' = Neovim $ ask


-- | Same as 'asks' for the 'InternalConfig'.
asks' :: (Config r st -> a) -> Neovim r st a
asks' = Neovim . asks

-- | Convenience alias for @'Neovim' () ()@.
type Neovim' = Neovim () ()


-- | Exceptions specific to /nvim-hs/.
data NeovimException
    = ErrorMessage Doc
    -- ^ Simply error message that is passed to neovim. It should currently only
    -- contain one line of text.
    deriving (Typeable, Show)


instance Exception NeovimException


instance IsString NeovimException where
    fromString = ErrorMessage . fromString


instance Pretty NeovimException where
    pretty = \case
        ErrorMessage s -> s


-- | Initialize a 'Neovim' context by supplying an 'InternalEnvironment'.
runNeovim :: Config r st
          -> st
          -> Neovim r st a
          -> IO (Either Doc (a, st))
runNeovim r st (Neovim a) = (try . runReaderT (runStateT (runResourceT a) st)) r >>= \case
    Left e -> case fromException e of
        Just e' ->
            return . Left . pretty $ (e' :: NeovimException)

        Nothing -> do
            liftIO . errorM "Context" $ "Converting Exception to Error message: " ++ show e
            (return . Left . text . show) e
    Right res -> (return . Right) res


-- | Fork a neovim thread with the given custom config value and a custom
-- state. The result of the thread is discarded and only the 'ThreadId' is
-- returend immediately.
-- FIXME This function is pretty much unused and mayhave undesired effects,
--       namely that you cannot register autocmds in the forked thread.
forkNeovim :: ir -> ist -> Neovim ir ist a -> Neovim r st ThreadId
forkNeovim r st a = do
    cfg <- ask'
    let threadConfig = cfg
            { pluginSettings = Nothing -- <- slightly problematic
            , customConfig = r
            }
    liftIO . forkIO . void $ runNeovim threadConfig st a


-- | Create a new unique function name. To prevent possible name clashes, digits
-- are stripped from the given suffix.
newUniqueFunctionName :: Neovim r st FunctionName
newUniqueFunctionName = do
    tu <- asks' uniqueCounter
    -- reverseing the integer string should distribute the first character more
    -- evently and hence cause faster termination for comparisons.
    fmap (F . U.fromString . reverse . show) . liftIO . atomically $ do
        u <- readTVar tu
        modifyTVar' tu succ
        return u


-- | This data type is used to dispatch a remote function call to the appopriate
-- recipient.
data FunctionType
    = Stateless ([Object] -> Neovim' Object)
    -- ^ 'Stateless' functions are simply executed with the sent arguments.

    | Stateful (TQueue SomeMessage)
    -- ^ 'Stateful' functions are handled within a special thread, the 'TQueue'
    -- is the communication endpoint for the arguments we have to pass.


instance Pretty FunctionType where
    pretty = \case
        Stateless _ -> blue $ text "\\os -> Neovim' o"
        Stateful  _ -> green $ text "\\os -> Neovim r st o"


-- | Type of the values stored in the function map.
type FunctionMapEntry = (FunctionalityDescription, FunctionType)


-- | A function map is a map containing the names of functions as keys and some
-- context dependent value which contains all the necessary information to
-- execute that function in the intended way.
--
-- This type is only used internally and handles two distinct cases. One case
-- is a direct function call, wich is simply a function that accepts a list of
-- 'Object' values and returns a result in the 'Neovim' context. The second
-- case is calling a function that has a persistent state. This is mediated to
-- a thread that reads from a 'TQueue'. (NB: persistent currently means, that
-- state is stored for as long as the plugin provider is running and not
-- restarted.)
type FunctionMap = Map FunctionName FunctionMapEntry


-- | Create a new function map from the given list of 'FunctionMapEntry' values.
mkFunctionMap :: [FunctionMapEntry] -> FunctionMap
mkFunctionMap = Map.fromList . map (\e -> (name (fst e), e))


-- | A wrapper for a reader value that contains extra fields required to
-- communicate with the messagepack-rpc components and provide necessary data to
-- provide other globally available operations.
--
-- Note that you most probably do not want to change the fields prefixed with an
-- underscore.
data Config r st = Config
    -- Global settings; initialized once
    { eventQueue        :: TQueue SomeMessage
    -- ^ A queue of messages that the event handler will propagate to
    -- appropriate threads and handlers.

    , transitionTo      :: MVar StateTransition
    -- ^ The main thread will wait for this 'MVar' to be filled with a value
    -- and then perform an action appropriate for the value of type
    -- 'StateTransition'.

    , providerName      :: TMVar (Either String Int)
    -- ^ Since nvim-hs must have its "Neovim.RPC.SocketReader" and
    -- "Neovim.RPC.EventHandler" running to determine the actual channel id
    -- (i.e. the 'Int' value here) this field can only be set properly later.
    -- Hence, the value of this field is put in an 'TMVar'.
    -- Name that is used to identify this provider. Assigning such a name is
    -- done in the neovim config (e.g. ~\/.nvim\/nvimrc).

    , uniqueCounter     :: TVar Integer
    -- ^ This 'TVar' is used to generate uniqe function names on the side of
    -- /nvim-hs/. This is useful if you don't want to overwrite existing
    -- functions or if you create autocmd functions.

    , globalFunctionMap :: TMVar FunctionMap
    -- ^ This map is used to dispatch received messagepack function calls to
    -- it's appropriate targets.

    -- Local settings; intialized for each stateful component
    , pluginSettings    :: Maybe (PluginSettings r st)
    -- ^ In a registered functionality this field contains a function (and
    -- possibly some context dependent values) to register new functionality.

    , customConfig      :: r
    -- ^ Plugin author supplyable custom configuration. Queried on the
    -- user-facing side with 'ask' or 'asks'.
    }


-- | Convenient helper to create a new config for the given state and read-only
-- config.
--
-- Sets the 'pluginSettings' field to 'Nothing'.
retypeConfig :: r -> st -> Config anotherR anotherSt -> Config r st
retypeConfig r _ cfg = cfg { pluginSettings = Nothing, customConfig = r }


-- | This GADT is used to share informatino between stateless and stateful
-- plugin threads since they work fundamentally in the same way. They both
-- contain a function to register some functionality in the plugin provider
-- as well as some values which are specific to the one or the other context.
data PluginSettings r st where
    StatelessSettings
        :: (FunctionalityDescription
            -> ([Object] -> Neovim' Object)
            -> Neovim' (Maybe FunctionMapEntry))
        -> PluginSettings () ()

    StatefulSettings
        :: (FunctionalityDescription
            -> ([Object] -> Neovim r st Object)
            -> TQueue SomeMessage
            -> TVar (Map FunctionName ([Object] -> Neovim r st Object))
            -> Neovim r st (Maybe FunctionMapEntry))
        -> TQueue SomeMessage
        -> TVar (Map FunctionName ([Object] -> Neovim r st Object))
        -> PluginSettings r st


-- | Create a new 'InternalConfig' object by providing the minimal amount of
-- necessary information.
--
-- This function should only be called once per /nvim-hs/ session since the
-- arguments are shared across processes.
newConfig :: IO (Maybe String) -> IO r -> IO (Config r context)
newConfig ioProviderName r = Config
    <$> newTQueueIO
    <*> newEmptyMVar
    <*> (maybe (atomically newEmptyTMVar) (newTMVarIO . Left) =<< ioProviderName)
    <*> newTVarIO 100
    <*> atomically newEmptyTMVar
    <*> pure Nothing
    <*> r


-- | The state that the plugin provider wants to transition to.
data StateTransition
    = Quit
    -- ^ Quit the plugin provider.

    | Restart
    -- ^ Restart the plugin provider.

    | Failure Doc
    -- ^ The plugin provider failed to start or some other error occured.

    | InitSuccess
    -- ^ The plugin provider started successfully.

    deriving (Show)
