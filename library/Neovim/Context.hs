{-# LANGUAGE LambdaCase #-}
{- |
Module      :  Neovim.Context
Description :  The Neovim context
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental

-}
module Neovim.Context (
    newUniqueFunctionName,

    Neovim,
    Neovim',
    NeovimException(..),
    FunctionMap,
    FunctionMapEntry,
    mkFunctionMap,
    runNeovim,
    forkNeovim,
    err,
    errOnInvalidResult,
    restart,
    quit,

    ask,
    asks,
    get,
    gets,
    put,
    modify,

    throwError,
    module Control.Monad.IO.Class,
    ) where


import           Neovim.Classes
import           Neovim.Context.Internal      (FunctionMap, FunctionMapEntry,
                                               Neovim, Neovim',
                                               NeovimException (ErrorMessage),
                                               forkNeovim, mkFunctionMap,
                                               newUniqueFunctionName, runNeovim)
import qualified Neovim.Context.Internal      as Internal

import           Control.Concurrent           (putMVar)
import           Control.Exception
import           Control.Monad.Except
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.MessagePack             (Object)
import           Text.PrettyPrint.ANSI.Leijen (Doc, text)


-- | @'throw'@ specialized to 'Doc'. If you do not care about pretty printing,
-- you can simply use 'text' in front of your string or use the
-- @OverloadedStrings@ extension to specify the error message.
err :: Doc ->  Neovim r st a
err = throw . ErrorMessage


errOnInvalidResult :: (NvimObject o) => Neovim r st (Either Object Object) -> Neovim r st o
errOnInvalidResult a = a >>= \case
    Left o ->
        (err . text . show) o

    Right o -> case fromObject o of
        Left e ->
            err e

        Right x ->
            return x


-- | Initiate a restart of the plugin provider.
restart :: Neovim r st ()
restart = liftIO . flip putMVar Internal.Restart =<< Internal.asks' Internal.transitionTo


-- | Initiate the termination of the plugin provider.
quit :: Neovim r st ()
quit = liftIO . flip putMVar Internal.Quit =<< Internal.asks' Internal.transitionTo

