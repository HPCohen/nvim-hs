{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
module Neovim.API.THSpec
    where

import           Neovim.API.THSpecFunctions

import           Neovim.API.TH
import           Neovim.Classes
import           Neovim.Context
import           Neovim.Plugin.Classes

import           Data.Default
import qualified Data.Map                   as Map

import           Test.Hspec
import           Test.QuickCheck

import           Control.Applicative
import           Control.Concurrent
import           Control.Concurrent.STM

call :: ([Object] -> Neovim () () Object) -> [Object]
     -> IO Object
call f args = do
    cfg <- ConfigWrapper <$> newTQueueIO
                         <*> newEmptyMVar
                         <*> pure "nvim-hs-test-suite"
                         <*> pure ()
    res <- fmap fst <$> runNeovim cfg () (f args)
    case res of
        Right x -> return x
        Left e -> throw $ ErrorMessage e



isNeovimException :: NeovimException -> Bool
isNeovimException _ = True

spec :: Spec
spec = do
  describe "calling function without an argument" $ do
    let EF (Function fname _, testFun) = $(function  "TestFunction0" 'testFunction0) def
    it "should have a capitalized prefix" $
        fname `shouldBe` "TestFunction0"
    it "should return the consant value" $
      call testFun [] `shouldReturn` ObjectInt 42
    it "should fail if supplied an argument" $
        call testFun [ObjectNil] `shouldThrow` isNeovimException

  describe "calling testFunction with two arguments" $ do
    let EF (Function fname _, testFun) = $(function' 'testFunction2) def
    it "should have a capitalized prefix" $
        fname `shouldBe` "TestFunction2"
    it "should return 2 for proper arguments" $
      call testFun [ObjectBinary "ignored", ObjectInt 42] `shouldReturn` ObjectDouble 2
    it "should throw an exception for the wrong number of arguments" $
      call testFun [] `shouldThrow` isNeovimException
    it "should throw an exception for incompatible types" $
      call testFun [ObjectBinary "ignored", ObjectNil] `shouldThrow` isNeovimException
    it "should cast arguments to similar types" $
      call testFun [ObjectString "ignored", ObjectFloat 42] `shouldReturn` ObjectDouble 2

  describe "generating a command from the two argument test function" $ do
      let EF (Command fname _, testFun) = $(command' 'testFunction2) def
      it "should capitalize the first character" $
        fname `shouldBe` "TestFunction2"

  describe "generating the test successor functions" $ do
      let EF (Function fname _, testFun) = $(function' 'testSucc) def
      it "should be named TestSucc" $
          fname `shouldBe` "TestSucc"
      it "should return the old value + 1" . property $
          \x -> call testFun [ObjectInt x] `shouldReturn` ObjectInt (x+1)

  describe "calling test function with a map argument" $ do
      let EF (Command cname _, testFun) = $(command "TestFunctionMap" 'testFunctionMap) def
      it "should capitalize the first letter" $
          cname `shouldBe` "TestFunctionMap"
      it "should fail for the wrong number of arguments" $
        call testFun [] `shouldThrow` isNeovimException
      it "should fail for the wrong type of arguments" $
        call testFun [ObjectInt 7, ObjectString "FOO"] `shouldThrow` isNeovimException
      it "should return Nothing for an empty map" $
          call testFun [toObject (Map.empty :: Map.Map String Int), ObjectString "FOO"]
            `shouldReturn` ObjectNil
      it "should return just the value for the singletion entry" $
          call testFun [toObject (Map.singleton "FOO" 7 :: Map.Map String Int), ObjectString "FOO"]
            `shouldReturn` ObjectInt 7
