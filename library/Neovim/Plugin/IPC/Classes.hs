{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
{- |
Module      :  Neovim.Plugin.IPC.Classes
Description :  Classes used for Inter Plugin Communication
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental
Portability :  GHC

-}
module Neovim.Plugin.IPC.Classes (
    SomeMessage(..),
    Message(..),
    FunctionCall(..),
    Request(..),
    Notification(..),

    module Data.Int,
    module Data.Time,
    ) where

import           Neovim.Plugin.Classes  (FunctionName)

import           Control.Concurrent.STM
import           Data.Data              (Typeable, cast)
import           Data.Int               (Int64)
import           Data.MessagePack
import           Data.Time

import           Prelude

-- | Taken from xmonad and based on ideas in /An Extensible Dynamically-Typed
-- Hierarchy of Exceptions/, Simon Marlow, 2006.
--
-- User-extensible messages must be put into a value of this type, so that it
-- can be sent to other plugins.
data SomeMessage = forall msg. Message msg => SomeMessage msg


-- | This class allows type safe casting of 'SomeMessage' to an actual message.
-- The cast is successful if the type you're expecting matches the type in the
-- 'SomeMessage' wrapper. This way, you can subscribe to an arbitrary message
-- type withouth having to pattern match on the constructors. This also allows
-- plugin authors to create their own message types without having to change the
-- core code of /nvim-hs/.
class Typeable message => Message message where
    -- | Try to convert a given message to a value of the message type we are
    -- interested in. Will evaluate to 'Nothing' for any other type.
    fromMessage :: SomeMessage -> Maybe message
    fromMessage (SomeMessage message) = cast message


-- | Haskell representation of supported Remote Procedure Call messages.
data FunctionCall
    = FunctionCall FunctionName [Object] (TMVar (Either Object Object)) UTCTime
    -- ^ Method name, parameters, callback, timestamp
    deriving (Typeable)


instance Message FunctionCall


-- | A request is a data type containing the method to call, its arguments and
-- an identifier used to map the result to the function that has been called.
data Request = Request
    { reqMethod :: FunctionName
    -- ^ Name of the function to call.
    , reqId     :: !Int64
    -- ^ Identifier to map the result to a function call invocation.
    , reqArgs   :: [Object]
    -- ^ Arguments for the function.
    } deriving (Eq, Ord, Show, Typeable)


instance Message Request


-- | A notification is similar to a 'Request'. It essentially does the same
-- thing, but the function is only called for its side effects. This type of
-- message is sent by neovim if the caller there does not care about the result
-- of the computation.
data Notification = Notification
    { notMethod :: FunctionName
    -- ^ Name of the function to call.
    , notArgs   :: [Object]
    -- ^ Arguments for the function.
    } deriving (Eq, Ord, Show, Typeable)


instance Message Notification

