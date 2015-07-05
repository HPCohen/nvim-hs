{-# LANGUAGE DeriveDataTypeable #-}
{- |
Module      :  Neovim.Plugin.IPC.Internal
Description :  Internally used parts of the inter plugin communication
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental
Portability :  GHC

-}
module Neovim.Plugin.IPC.Internal
    ( RPCMessage(..)
    , Request(..)
    , Notification(..)

    , module Data.Int
    , module Data.Time
    ) where

import           Control.Concurrent.STM
import           Data.Data                 (Typeable)
import           Data.Int                  (Int64)
import           Data.MessagePack
import           Data.Text                 (Text)
import           Data.Time
import           Neovim.Plugin.IPC.Classes

-- | Haskell representation of supported Remote Procedure Call messages.
data RPCMessage
    = FunctionCall Text [Object] (TMVar (Either Object Object)) UTCTime
    -- ^ Method name, parameters, callback, timestamp
    | Response !Int64 Object Object
    -- ^ Response sent to indicate the result of a function call.
    --
    -- * identfier of the message as 'Word32'
    -- * Error value
    -- * Result value
    | NotificationCall Text [Object]
    -- ^ Method name and parameters.
    deriving (Typeable)

instance Message RPCMessage

-- | A request is a data type containing the method to call, its arguments and
-- an identifier used to map the result to the function that has been called.
data Request = Request
    { reqMethod :: Text
    -- ^ Name of the function to call.
    , reqId     :: !Int64
    -- ^ Identifier to map the result to a function call invocation.
    , reqArgs   :: [Object]
    -- ^ Arguments for the function.
    } deriving (Typeable)

instance Message Request

-- | A notification is similar to a 'Request'. It essentially does the same
-- thing, but the function is only called for its side effects. This type of
-- message is sent by neovim if the caller there does not care about the result
-- of the computation.
data Notification = Notification
    { notMethod :: Text
    -- ^ Name of the function to call.
    , notArgs   :: [Object]
    -- ^ Argumentse for the function.
    } deriving (Typeable)

instance Message Notification

