module PubSubSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Data.IORef
import Service.PubSub
import Audit.CommandMeta (CommandMeta(..), defaultMeta)

spec :: Spec
spec = do
    -- 9.1: TopicBus unit tests
    describe "TopicBus" $ do
        describe "newTopicBus" $ do
            it "creates a bus with no subscribers" $ do
                bus <- newTopicBus :: IO (TopicBus String)
                publish bus (Topic "test") "hello"

        describe "subscribe + publish" $ do
            it "delivers events matching a wildcard pattern" $ do
                bus <- newTopicBus
                ref <- newIORef []
                _ <- subscribe bus ".*" $ \(Topic t) e ->
                    modifyIORef ref ((t, e) :)
                publish bus (Topic "skill.create.4") "created"
                publish bus (Topic "station.add.1") "added"
                got <- readIORef ref
                reverse got `shouldBe`
                    [ ("skill.create.4", "created")
                    , ("station.add.1", "added")
                    ]

            it "delivers only to matching subscribers (prefix pattern)" $ do
                bus <- newTopicBus
                skillRef <- newIORef []
                stationRef <- newIORef []
                _ <- subscribe bus "skill\\..*" $ \_t e ->
                    modifyIORef skillRef (e :)
                _ <- subscribe bus "station\\..*" $ \_t e ->
                    modifyIORef stationRef (e :)
                publish bus (Topic "skill.create.4") "s1"
                publish bus (Topic "station.add.1") "s2"
                publish bus (Topic "skill.delete.4") "s3"
                readIORef skillRef >>= (`shouldBe` ["s3", "s1"]) . id
                readIORef stationRef >>= (`shouldBe` ["s2"]) . id

            it "does not deliver to non-matching subscribers" $ do
                bus <- newTopicBus
                ref <- newIORef (0 :: Int)
                _ <- subscribe bus "skill\\..*" $ \_t _e ->
                    modifyIORef ref (+ 1)
                publish bus (Topic "station.add.1") ()
                readIORef ref `shouldReturn` 0

            it "delivers to multiple subscribers on same pattern" $ do
                bus <- newTopicBus
                ref1 <- newIORef (0 :: Int)
                ref2 <- newIORef (0 :: Int)
                _ <- subscribe bus ".*" $ \_t n -> modifyIORef ref1 (+ n)
                _ <- subscribe bus ".*" $ \_t n -> modifyIORef ref2 (+ n)
                publish bus (Topic "test") (10 :: Int)
                readIORef ref1 `shouldReturn` 10
                readIORef ref2 `shouldReturn` 10

        describe "unsubscribe" $ do
            it "stops delivering events after unsubscribe" $ do
                bus <- newTopicBus
                ref <- newIORef (0 :: Int)
                sid <- subscribe bus ".*" $ \_t n -> modifyIORef ref (+ n)
                publish bus (Topic "a") (1 :: Int)
                unsubscribe bus sid
                publish bus (Topic "b") (100 :: Int)
                readIORef ref `shouldReturn` 1

            it "does not affect other subscribers" $ do
                bus <- newTopicBus
                ref1 <- newIORef []
                ref2 <- newIORef []
                sid1 <- subscribe bus ".*" $ \_t e -> modifyIORef ref1 (e :)
                _    <- subscribe bus ".*" $ \_t e -> modifyIORef ref2 (e :)
                publish bus (Topic "x") "before"
                unsubscribe bus sid1
                publish bus (Topic "y") "after"
                reverse <$> readIORef ref1 `shouldReturn` ["before"]
                reverse <$> readIORef ref2 `shouldReturn` ["before", "after"]

        describe "thread safety" $ do
            it "handles concurrent publishes without losing events" $ do
                bus <- newTopicBus
                ref <- newIORef (0 :: Int)
                _ <- subscribe bus ".*" $ \_t n -> modifyIORef ref (+ n)
                let n = 100
                done <- newEmptyMVar
                _ <- forkIO $ do
                    mapM_ (\i -> publish bus (Topic "a") i) [1..n]
                    putMVar done ()
                _ <- forkIO $ do
                    mapM_ (\i -> publish bus (Topic "b") i) [1..n]
                    putMVar done ()
                takeMVar done
                takeMVar done
                total <- readIORef ref
                total `shouldBe` (2 * sum [1..n])

    -- 9.2: buildTopic unit tests
    describe "buildTopic" $ do
        it "builds topic from full metadata" $ do
            let meta = defaultMeta
                    { cmEntityType = Just "skill"
                    , cmOperation = Just "create"
                    , cmEntityId = Just 4
                    }
            buildTopic meta `shouldBe` Topic "skill.create.4"

        it "builds topic with missing entity ID" $ do
            let meta = defaultMeta
                    { cmEntityType = Just "config"
                    , cmOperation = Just "reset"
                    }
            buildTopic meta `shouldBe` Topic "config.reset"

        it "builds topic with missing fields" $ do
            let meta = defaultMeta
                    { cmEntityType = Just "skill"
                    }
            buildTopic meta `shouldBe` Topic "skill"

        it "builds empty topic for unrecognized command" $ do
            buildTopic defaultMeta `shouldBe` Topic ""

    -- 9.3: CommandEvent construction and publishCommand
    describe "publishCommand" $ do
        it "publishes a CommandEvent with correct fields" $ do
            bus <- newTopicBus
            ref <- newIORef Nothing
            _ <- subscribe bus "skill\\.create\\..*" $ \topic event ->
                writeIORef ref (Just (topic, event))
            publishCommand bus RPC "admin" "skill create 4 pastry"
            result <- readIORef ref
            case result of
                Nothing -> expectationFailure "expected event to be delivered"
                Just (topic, event) -> do
                    topic `shouldBe` Topic "skill.create.4"
                    ceCommand event `shouldBe` "skill create 4 pastry"
                    ceSource event `shouldBe` RPC
                    ceUsername event `shouldBe` "admin"

        it "delivers to wildcard subscriber" $ do
            bus <- newTopicBus
            ref <- newIORef (0 :: Int)
            _ <- subscribe bus ".*" $ \_t _e -> modifyIORef ref (+ 1)
            publishCommand bus CLI "user1" "station add 1 grill"
            readIORef ref `shouldReturn` 1

    describe "sourceString" $ do
        it "converts CLI to \"cli\"" $ sourceString CLI `shouldBe` "cli"
        it "converts RPC to \"rpc\"" $ sourceString RPC `shouldBe` "rpc"
        it "converts GUI to \"gui\"" $ sourceString GUI `shouldBe` "gui"
        it "converts Demo to \"demo\"" $ sourceString Demo `shouldBe` "demo"
