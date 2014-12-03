{- |
Module      :  NVim
Description :  Prelude for neovim
Copyright   :  (c) Sebastian Witte
License     :  Apache-2.0

Maintainer  :  woozletoff@gmail.com
Stability   :  experimental

This module should export all modules and functions which are generally
useful for plugin developement for neovim.
-}
module Neovim (
    module Neovim.API.Classes,
    module Neovim.API.String,
    module Neovim.Main,
    module Neovim.Config,
    ) where

import Neovim.Main (neovim)
import Neovim.API.String
import Neovim.API.Classes
import Neovim.Config
