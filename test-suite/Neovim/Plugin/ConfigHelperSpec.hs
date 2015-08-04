module Neovim.Plugin.ConfigHelperSpec
    where

import           Test.Hspec
import           Test.HUnit                          (assertFailure)

import           Neovim.Plugin.ConfigHelper.Internal
import           Neovim.Quickfix

import           Text.Parsec                         hiding (Error)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False

isRight :: Either a b -> Bool
isRight = not . isLeft

spec :: Spec
spec = do
  describe "parseQuickFfixItems" $ do
    it "should match this test file 1" $ do
      e <- readFile "./test-files/compile-error-for-quickfix-test1"
      let [qs] = parseQuickfixItems e
      bufOrFile qs `shouldBe` Right "/.config/nvim/nvim.hs"
      lnumOrPattern qs `shouldBe` Left 25
      col qs `shouldBe` Just (30, True)
      nr qs `shouldBe` Nothing
      errorType qs `shouldBe` Error

    it "should match this test file 2" $ do
      e <- readFile "./test-files/compile-error-for-quickfix-test2"
      let [qs] = parseQuickfixItems e
      bufOrFile qs `shouldBe` Right "/.config/nvim/lib/TestPlugins.hs"
      lnumOrPattern qs `shouldBe` Left 11
      col qs `shouldBe` Just (18, True)
      nr qs `shouldBe` Nothing
      errorType qs `shouldBe` Error

    it "should match this test file 3" $ do
      e <- readFile "./test-files/compile-error-for-quickfix-test3"
      let [qs] = parseQuickfixItems e
      bufOrFile qs `shouldBe` Right "/.config/nvim/nvim.hs"
      lnumOrPattern qs `shouldBe` Left 25
      col qs `shouldBe` Just (30, True)
      nr qs `shouldBe` Nothing
      errorType qs `shouldBe` Error

    it "should match this test file 4" $ do
      e <- readFile "./test-files/compile-error-for-quickfix-test4"
      let [qs] = parseQuickfixItems e
      bufOrFile qs `shouldBe` Right "/.config/nvim/lib/TestPlugins.hs"
      lnumOrPattern qs `shouldBe` Left 23
      col qs `shouldBe` Just (9, True)
      nr qs `shouldBe` Nothing
      errorType qs `shouldBe` Error

    it "should match this test file 5" $ do
      e <- readFile "./test-files/compile-error-for-quickfix-test5"
      let [q1,q2] = parseQuickfixItems e
      bufOrFile q1 `shouldBe` Right "/.config/nvim/lib/TestPlugins.hs"
      bufOrFile q2 `shouldBe` Right "/.config/nvim/lib/TestPlugins.hs"
      lnumOrPattern q1 `shouldBe` Left 23
      lnumOrPattern q2 `shouldBe` Left 23
      col q1 `shouldBe` Just (9, True)
      col q2 `shouldBe` Just (32, True)
      nr q1 `shouldBe` Nothing
      nr q2 `shouldBe` Nothing
      errorType q1 `shouldBe` Warning
      errorType q2 `shouldBe` Warning

    it "should parse all files concatenated" $ do
      e1 <- readFile "./test-files/compile-error-for-quickfix-test1"
      e2 <- readFile "./test-files/compile-error-for-quickfix-test2"
      e3 <- readFile "./test-files/compile-error-for-quickfix-test3"
      let qs = parseQuickfixItems $ unlines [e1,e2,e3]
      length qs `shouldBe` 3
      case qs of
          [q1, q2, q3] -> do
              lnumOrPattern q1 `shouldBe` Left 25
              lnumOrPattern q2 `shouldBe` Left 11
              lnumOrPattern q3 `shouldBe` Left 25
          _ -> assertFailure "Expected three quickfix list items."

  describe "pShortDesrciption" $ do
    it "should fail for an empty input" $
      parse pShortDesrciption "" "" `shouldSatisfy` isLeft
    it "should fail for an input solely consisting of spaces followed by a newline" $
      parse pShortDesrciption "" " \t \t\t \n" `shouldSatisfy` isLeft
    it "should parse this simple expression" $
      parse pShortDesrciption "" "this simple expression\n"
        `shouldBe` Right "this simple expression"

  describe "pLongDescription" $ do
    it "should parse anything until there is a blank line" $ do
      parse pLongDescription "" "\n\n"
        `shouldBe` Right ""
      parse pLongDescription "" "test\n    \n"
        `shouldBe` Right "test"
      parse pLongDescription "" "test\n    ibus\n \n"
        `shouldBe` Right "test\n    ibus"

