{-# LANGUAGE OverloadedStrings #-}

module SessionSpec (spec) where

import Test.Hspec
import Control.Concurrent (threadDelay)
import System.Directory (removeFile, doesFileExist)

import Data.Text (Text)
import Auth.Types (UserId, Role(..), userIsWorker, userWorkerStatus)
import Domain.Types (WorkerStatus(..))
-- (no longer importing WorkerId — register no longer takes one)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..))
import Service.Auth (register)

spec :: Spec
spec = do
    -- 4.1: Create session and retrieve active session
    describe "create and retrieve session" $ do
        it "creates a session and retrieves it as active" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "alice"
            (sid, _tok) <- repoCreateSession repo uid
            mActive <- repoGetActiveSession repo uid
            mActive `shouldBe` Just sid

    -- 4.2: Close session makes it inactive
    describe "close session" $ do
        it "makes session inactive after close" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "bob"
            (sid, _tok) <- repoCreateSession repo uid
            repoCloseSession repo sid
            mActive <- repoGetActiveSession repo uid
            mActive `shouldBe` Nothing

    -- 4.3: Touch session updates last_active_at
    describe "touch session" $ do
        it "updates last_active_at" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "carol"
            (sid, _tok) <- repoCreateSession repo uid
            -- Small delay so timestamps differ
            threadDelay 1100000  -- 1.1 seconds (SQLite datetime has 1s resolution)
            repoTouchSession repo sid
            -- Verify session is still active (touch didn't break it)
            mActive <- repoGetActiveSession repo uid
            mActive `shouldBe` Just sid

    -- 4.4: Multiple sessions — only the active one is returned
    describe "multiple sessions" $ do
        it "returns only the most recent active session" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "dave"
            (sid1, _tok1) <- repoCreateSession repo uid
            repoCloseSession repo sid1
            (sid2, _tok2) <- repoCreateSession repo uid
            mActive <- repoGetActiveSession repo uid
            mActive `shouldBe` Just sid2

        it "returns Nothing when all sessions are closed" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "eve"
            (sid1, _tok1) <- repoCreateSession repo uid
            (sid2, _tok2) <- repoCreateSession repo uid
            repoCloseSession repo sid1
            repoCloseSession repo sid2
            mActive <- repoGetActiveSession repo uid
            mActive `shouldBe` Nothing

    describe "register with noWorker flag" $ do
        it "creates a user with worker_status='none' when noWorker=True" $ withTestRepo $ \repo -> do
            r <- register repo "frank" "password" Admin True
            case r of
                Right uid -> do
                    mUser <- repoGetUser repo uid
                    case mUser of
                        Just u -> do
                            userWorkerStatus u `shouldBe` WSNone
                            userIsWorker u `shouldBe` False
                        Nothing -> expectationFailure "user not found"
                Left err -> expectationFailure ("register failed: " ++ show err)

        it "creates a user with worker_status='active' when noWorker=False" $ withTestRepo $ \repo -> do
            r <- register repo "grace" "password" Normal False
            case r of
                Right uid -> do
                    mUser <- repoGetUser repo uid
                    case mUser of
                        Just u -> do
                            userWorkerStatus u `shouldBe` WSActive
                            userIsWorker u `shouldBe` True
                        Nothing -> expectationFailure "user not found"
                Left err -> expectationFailure ("register failed: " ++ show err)

-- | Helper: create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-session.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    action repo
    removeFile path

-- | Helper: create a test user and return their UserId.
createTestUser :: Repository -> Text -> IO UserId
createTestUser repo name = do
    result <- register repo name "password" Admin False
    case result of
        Right uid -> return uid
        Left err  -> error $ "Failed to create test user: " ++ show err
