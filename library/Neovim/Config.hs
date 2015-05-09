{- |
Module      :  Neovim.Config
Description :  The user editable and compilable configuration
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental

-}
module Neovim.Config (
    NeovimConfig(..),
    module Data.Default,
    module System.Log,
    ) where

import           Neovim.API.Plugin

import           Data.Default      (Default (def))
import           System.Log        (Priority (..))

data NeovimConfig = Config
    { plugins      :: [IO SomePlugin]
    , errorMessage :: Maybe String
    -- ^ Used by "Dyre" for storing compilation errors.
    , logOptions   :: Maybe (FilePath, Priority)
    -- ^ Set the general logging options.
    }

instance Default NeovimConfig where
    def = Config
            { plugins      = []
            , errorMessage = Nothing
            , logOptions   = Nothing
            }

