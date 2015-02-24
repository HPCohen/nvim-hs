{- |
Module      :  Neovim.Debug
Description :  Debugging facilities
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental

-}
module Neovim.Debug (
    disableLogger,
    withLogger,

    module System.Log.Logger,
    ) where

import System.Log.Logger
import System.Log.Handler.Simple
import Control.Exception

-- | Disable logging to stderr.
disableLogger :: IO a -> IO a
disableLogger action = do
    updateGlobalLogger rootLoggerName removeHandler
    action

-- | Initialize the root logger to avoid stderr and set it to log the given
-- file instead. Simply wrap the main entry point with this function to
-- initialze the logger.
-- @
-- main = withLogger "/home/dude/nvim.log" Debug $ do
--     putStrLn "Hello, World!"
-- @
withLogger :: FilePath -> Priority -> IO a -> IO a
withLogger fp p action = bracket
    setupRootLogger
    (\fh -> closeFunc fh (privData fh))
    (const action)
  where
    setupRootLogger = do
        -- We shouldn't log to stderr or stdout as it is not unlikely that our
        -- messagepack communication is handled via those channels.
        disableLogger (return ())
        -- Log to the given file instead
        fh <- fileHandler fp p
        -- Adjust the log level as well
        updateGlobalLogger rootLoggerName (setLevel p . addHandler fh)
        -- For good measure, log some debug information
        logM "Neovim.Debug" DEBUG $
            unwords ["Initialized root looger with priority", show p, "and file: ", fp]
        return fh


