module PubSubSpec (spec) where

import Test.Hspec
import Data.IORef
import Service.PubSub

spec :: Spec
spec = do
    describe "newPubSub" $ do
        it "creates a bus with no subscribers" $ do
            bus <- newPubSub :: IO (PubSub String)
            -- publishing to empty bus should not error
            publish bus "hello"

    describe "subscribe + publish" $ do
        it "delivers events to a single subscriber" $ do
            bus <- newPubSub
            ref <- newIORef []
            _ <- subscribe bus $ \e -> modifyIORef ref (e :)
            publish bus "a"
            publish bus "b"
            got <- readIORef ref
            reverse got `shouldBe` ["a", "b"]

        it "delivers events to multiple subscribers" $ do
            bus <- newPubSub
            ref1 <- newIORef (0 :: Int)
            ref2 <- newIORef (0 :: Int)
            _ <- subscribe bus $ \n -> modifyIORef ref1 (+ n)
            _ <- subscribe bus $ \n -> modifyIORef ref2 (+ n)
            publish bus (10 :: Int)
            readIORef ref1 `shouldReturn` 10
            readIORef ref2 `shouldReturn` 10

    describe "unsubscribe" $ do
        it "stops delivering events after unsubscribe" $ do
            bus <- newPubSub
            ref <- newIORef (0 :: Int)
            sid <- subscribe bus $ \n -> modifyIORef ref (+ n)
            publish bus (1 :: Int)
            unsubscribe bus sid
            publish bus (100 :: Int)
            readIORef ref `shouldReturn` 1

        it "does not affect other subscribers" $ do
            bus <- newPubSub
            ref1 <- newIORef []
            ref2 <- newIORef []
            sid1 <- subscribe bus $ \e -> modifyIORef ref1 (e :)
            _    <- subscribe bus $ \e -> modifyIORef ref2 (e :)
            publish bus "before"
            unsubscribe bus sid1
            publish bus "after"
            reverse <$> readIORef ref1 `shouldReturn` ["before"]
            reverse <$> readIORef ref2 `shouldReturn` ["before", "after"]
