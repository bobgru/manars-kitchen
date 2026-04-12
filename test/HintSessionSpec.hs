module HintSessionSpec (spec) where

import Test.Hspec
import System.Directory (removeFile, doesFileExist)

import Auth.Types (UserId, Role(..))
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), Slot(..))
import Domain.Hint (Hint(..))
import Data.Time (TimeOfDay(..), fromGregorian)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), HintSessionRecord(..), AuditEntry(..))
import Service.Auth (register)

spec :: Spec
spec = do
    describe "hint session persistence" $ do
        it "save and load round-trips" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "alice"
            (sid, _tok) <- repoCreateSession repo uid
            let hints = [ GrantSkill (WorkerId 3) (SkillId 2)
                        , CloseStation (StationId 1) testSlot
                        ]
            repoSaveHintSession repo sid 1 hints 42
            result <- repoLoadHintSession repo sid 1
            result `shouldBe` Just (HintSessionRecord hints 42)

        it "returns Nothing for nonexistent session" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "bob"
            (sid, _tok) <- repoCreateSession repo uid
            result <- repoLoadHintSession repo sid 99
            result `shouldBe` Nothing

        it "upsert overwrites existing session" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "carol"
            (sid, _tok) <- repoCreateSession repo uid
            let hints1 = [GrantSkill (WorkerId 1) (SkillId 1)]
                hints2 = [WaiveOvertime (WorkerId 2)]
            repoSaveHintSession repo sid 1 hints1 10
            repoSaveHintSession repo sid 1 hints2 20
            result <- repoLoadHintSession repo sid 1
            result `shouldBe` Just (HintSessionRecord hints2 20)

        it "delete removes session" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "dave"
            (sid, _tok) <- repoCreateSession repo uid
            let hints = [WaiveOvertime (WorkerId 1)]
            repoSaveHintSession repo sid 1 hints 5
            repoDeleteHintSession repo sid 1
            result <- repoLoadHintSession repo sid 1
            result `shouldBe` Nothing

        it "delete nonexistent is a no-op" $ withTestRepo $ \repo -> do
            uid <- createTestUser repo "eve"
            (sid, _tok) <- repoCreateSession repo uid
            repoDeleteHintSession repo sid 99  -- should not error

    describe "audit-since query" $ do
        it "returns only mutations after checkpoint" $ withTestRepo $ \repo -> do
            _ <- createTestUser repo "frank"
            -- Log some commands (mutations)
            repoLogCommand repo "frank" "worker grant-skill 1 2"
            repoLogCommand repo "frank" "station add 3 dishwash"
            -- Get the audit log to find the IDs
            entries <- repoGetAuditLog repo
            let checkpoint = case entries of
                    []  -> 0
                    _   -> aeId (last entries)
            -- Log more commands
            repoLogCommand repo "frank" "worker set-hours 1 40"
            -- Query since checkpoint
            since <- repoAuditSince repo checkpoint
            length since `shouldBe` 1
            case since of
                [entry] -> aeCommand entry `shouldBe` Just "worker set-hours 1 40"
                _       -> expectationFailure ("Expected 1 entry, got " ++ show (length since))

        it "returns empty list when nothing since checkpoint" $ withTestRepo $ \repo -> do
            _ <- createTestUser repo "grace"
            repoLogCommand repo "grace" "station add 1 grill"
            entries <- repoGetAuditLog repo
            let checkpoint = aeId (last entries)
            since <- repoAuditSince repo checkpoint
            since `shouldBe` []

testSlot :: Slot
testSlot = Slot (fromGregorian 2026 5 4) (TimeOfDay 9 0 0) 3600

-- | Helper: create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-hint-session.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    action repo
    removeFile path

-- | Helper: create a test user and return their UserId.
createTestUser :: Repository -> String -> IO UserId
createTestUser repo name = do
    result <- register repo name "password" Admin (WorkerId 1)
    case result of
        Right uid -> return uid
        Left err  -> error $ "Failed to create test user: " ++ show err
