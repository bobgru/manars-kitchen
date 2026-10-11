{-# LANGUAGE OverloadedStrings #-}

module HintSessionSpec (spec) where

import Test.Hspec
import System.Directory (removeFile, doesFileExist)

import Data.Text (Text)
import Auth.Types (UserId, Role(..))
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), Slot(..))
import Domain.Hint (Hint(..))
import Data.Time (TimeOfDay(..), fromGregorian)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), HintSessionRecord(..), AuditEntry(..))
import Service.Auth (register)
import CLI.App (registerAuditSubscriber)
import Service.PubSub (TopicBus, CommandEvent, Source(..), newTopicBus, publishCommand)

spec :: Spec
spec = do
    describe "what-if session persistence (one per draft, ADR 0013)" $ do
        it "save and load round-trips" $ withTestRepo $ \(repo, _bus) -> do
            uid <- createTestUser repo "alice"
            _ <- repoCreateSession repo uid
            let hints = [ GrantSkill (WorkerId 3) (SkillId 2)
                        , CloseStation (StationId 1) testSlot
                        ]
            repoSaveHintSession repo 1 hints 42
            result <- repoLoadHintSession repo 1
            result `shouldBe` Just (HintSessionRecord hints 42)

        it "returns Nothing for a draft with no session" $ withTestRepo $ \(repo, _bus) -> do
            uid <- createTestUser repo "bob"
            _ <- repoCreateSession repo uid
            result <- repoLoadHintSession repo 99
            result `shouldBe` Nothing

        it "a second save replaces the draft's session" $ withTestRepo $ \(repo, _bus) -> do
            uid <- createTestUser repo "carol"
            _ <- repoCreateSession repo uid
            let hints1 = [GrantSkill (WorkerId 1) (SkillId 1)]
                hints2 = [WaiveOvertime (WorkerId 2)]
            repoSaveHintSession repo 1 hints1 10
            repoSaveHintSession repo 1 hints2 20
            result <- repoLoadHintSession repo 1
            result `shouldBe` Just (HintSessionRecord hints2 20)

        it "delete removes session" $ withTestRepo $ \(repo, _bus) -> do
            uid <- createTestUser repo "dave"
            _ <- repoCreateSession repo uid
            let hints = [WaiveOvertime (WorkerId 1)]
            repoSaveHintSession repo 1 hints 5
            repoDeleteHintSession repo 1
            result <- repoLoadHintSession repo 1
            result `shouldBe` Nothing

        it "delete nonexistent is a no-op" $ withTestRepo $ \(repo, _bus) -> do
            uid <- createTestUser repo "eve"
            _ <- repoCreateSession repo uid
            repoDeleteHintSession repo 99  -- should not error

    describe "audit-since query" $ do
        it "returns only mutations after checkpoint" $ withTestRepo $ \(repo, bus) -> do
            _ <- createTestUser repo "frank"
            -- Log some commands (mutations)
            publishCommand bus CLI "frank" "worker grant-skill 1 2"
            publishCommand bus CLI "frank" "station add 3 dishwash"
            -- Get the audit log to find the IDs
            entries <- repoGetAuditLog repo
            let checkpoint = case entries of
                    []  -> 0
                    _   -> aeId (last entries)
            -- Log more commands
            publishCommand bus CLI "frank" "worker set-hours 1 40"
            -- Query since checkpoint
            since <- repoAuditSince repo checkpoint
            length since `shouldBe` 1
            case since of
                [entry] -> aeCommand entry `shouldBe` Just "worker set-hours 1 40"
                _       -> expectationFailure ("Expected 1 entry, got " ++ show (length since))

        it "returns empty list when nothing since checkpoint" $ withTestRepo $ \(repo, bus) -> do
            _ <- createTestUser repo "grace"
            publishCommand bus CLI "grace" "station add 1 grill"
            entries <- repoGetAuditLog repo
            let checkpoint = aeId (last entries)
            since <- repoAuditSince repo checkpoint
            since `shouldBe` []

testSlot :: Slot
testSlot = Slot (fromGregorian 2026 5 4) (TimeOfDay 9 0 0) 3600

-- | Helper: create a temporary SQLite repo with pub/sub bus for testing.
withTestRepo :: ((Repository, TopicBus CommandEvent) -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-hint-session.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    bus <- newTopicBus
    _ <- registerAuditSubscriber bus repo
    action (repo, bus)
    removeFile path

-- | Helper: create a test user and return their UserId.
createTestUser :: Repository -> Text -> IO UserId
createTestUser repo name = do
    result <- register repo name "password" Admin False
    case result of
        Right uid -> return uid
        Left err  -> error $ "Failed to create test user: " ++ show err
