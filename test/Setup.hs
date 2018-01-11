{-# START_FILE Setup.hs #-}
{-# START_FILE test/Spec.hs #-}
-- {-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Distribution.Simple
import Lib (app)
import Test.Hspec
import Test.Hspec.Wai
import Test.Hspec.Wai.JSON

main = defaultMain
main :: IO ()
main = hspec spec

spec :: Spec
spec = with (return app) $ do
    describe "GET /users" $ do
        it "responds with 200" $ do
            get "/users" `shouldRespondWith` 200
        it "responds with [User]" $ do
            let users = "[{\"userId\":1,\"userFirstName\":\"Isaac\",\"userLastName\":\"Newton\"},{\"userId\":2,\"userFirstName\":\"Albert\",\"userLastName\":\"Einstein\"}]"
            get "/users" `shouldRespondWith` users

