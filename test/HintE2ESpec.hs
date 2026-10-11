{-# LANGUAGE OverloadedStrings #-}

module HintE2ESpec (spec) where

import Test.Hspec
import System.Directory (removeFile, doesFileExist)
import Data.Time (TimeOfDay(..), fromGregorian)

import Data.Text (Text)
import Auth.Types (UserId, Role(..))
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), Slot(..))
import Domain.Hint (Hint(..))
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), HintSessionRecord(..), AuditEntry(..))
import Service.Auth (register)
import Service.HintRebase (ChangeCategory(..), RebaseResult(..), classifyChange, rebaseSession)
import qualified Service.Draft as Draft
import CLI.App (registerAuditSubscriber)
import Service.PubSub (TopicBus, CommandEvent, Source(..), newTopicBus, publishCommand)

spec :: Spec
spec = do
    describe "E2E: hint session persistence across sessions" $ do
        it "add hints, close session, open new session, resume — hints preserved" $
            withTestRepo $ \(repo, bus) -> do
                -- Session 1: create user, session, draft, save hints
                uid <- createTestUser repo "alice"
                (sid1, _tok1) <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [ GrantSkill (WorkerId 3) (SkillId 2)
                            , WaiveOvertime (WorkerId 5)
                            ]
                -- Log a command to establish a checkpoint
                publishCommand bus CLI "alice" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                -- Save hint session
                repoSaveHintSession repo did hints cp
                -- Close session 1
                repoCloseSession repo sid1

                -- Session 2: a new login finds the draft's what-ifs, because
                -- they are the draft's, not the login's (ADR 0013).
                (_sid2, _tok2) <- repoCreateSession repo uid
                result2 <- repoLoadHintSession repo did
                result2 `shouldBe` Just (HintSessionRecord hints cp)
                -- Verify the hints are exactly what we saved
                let HintSessionRecord loadedHints loadedCp = case result2 of
                        Just r  -> r
                        Nothing -> error "Expected to find persisted session"
                loadedHints `shouldBe` hints
                loadedCp `shouldBe` cp

    describe "E2E: rebase with compatible change" $ do
        it "hints preserved after compatible mutation" $
            withTestRepo $ \(repo, bus) -> do
                uid <- createTestUser repo "bob"
                _ <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [GrantSkill (WorkerId 3) (SkillId 2)]
                -- Establish checkpoint
                publishCommand bus CLI "bob" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                -- Save hint session
                repoSaveHintSession repo did hints cp
                -- Make a compatible mutation (different station, doesn't touch worker 3 or skill 2)
                publishCommand bus CLI "bob" "station create 5 dishwash"
                -- Get entries since checkpoint
                since <- repoAuditSince repo cp
                length since `shouldBe` 1
                -- Classify via rebaseSession
                let result = rebaseSession did since hints
                case result of
                    AutoRebase n -> n `shouldBe` 1
                    other -> expectationFailure
                        ("Expected AutoRebase, got: " ++ show other)
                -- After auto-rebase, update checkpoint and re-save
                allEntries <- repoGetAuditLog repo
                let newCp = aeId (last allEntries)
                repoSaveHintSession repo did hints newCp
                -- Verify hints are still intact
                loaded <- repoLoadHintSession repo did
                loaded `shouldBe` Just (HintSessionRecord hints newCp)

    describe "E2E: rebase with conflicting change" $ do
        it "conflict detected and resolvable by dropping conflicting hints" $
            withTestRepo $ \(repo, bus) -> do
                uid <- createTestUser repo "carol"
                _ <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [ GrantSkill (WorkerId 3) (SkillId 2)
                            , WaiveOvertime (WorkerId 5)
                            ]
                -- Establish checkpoint
                publishCommand bus CLI "carol" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                repoSaveHintSession repo did hints cp
                -- Make a conflicting mutation: revoke the exact skill we're granting
                publishCommand bus CLI "carol" "worker revoke-skill 3 2"
                -- Get entries since checkpoint
                since <- repoAuditSince repo cp
                length since `shouldBe` 1
                -- Classify
                let result = rebaseSession did since hints
                case result of
                    HasConflicts classified -> do
                        -- Should have exactly one conflicting entry
                        let conflicts = [(e, c) | (e, c) <- classified, c == Conflicting]
                        length conflicts `shouldBe` 1
                        -- Simulate "drop conflicting hints": filter out hints that
                        -- conflict with any of the conflicting audit entries
                        let conflictingEntries = [e | (e, Conflicting) <- classified]
                            safeHints = filter
                                (\h -> not (any
                                    (\e -> classifyChange did e [h] == Conflicting)
                                    conflictingEntries))
                                hints
                        -- GrantSkill (3, 2) should be dropped, WaiveOvertime (5) should survive
                        length safeHints `shouldBe` 1
                        case safeHints of
                            [h] -> h `shouldBe` WaiveOvertime (WorkerId 5)
                            _   -> expectationFailure "Expected exactly one safe hint"
                        -- Save the safe hints
                        allEntries <- repoGetAuditLog repo
                        let newCp = aeId (last allEntries)
                        repoSaveHintSession repo did safeHints newCp
                        loaded <- repoLoadHintSession repo did
                        loaded `shouldBe` Just (HintSessionRecord safeHints newCp)
                    other -> expectationFailure
                        ("Expected HasConflicts, got: " ++ show other)

        it "structural change (draft commit) invalidates session" $
            withTestRepo $ \(repo, bus) -> do
                uid <- createTestUser repo "dave"
                _ <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [GrantSkill (WorkerId 3) (SkillId 2)]
                publishCommand bus CLI "dave" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                repoSaveHintSession repo did hints cp
                -- Simulate draft commit appearing in audit log
                publishCommand bus CLI "dave" ("draft commit " ++ show did)
                since <- repoAuditSince repo cp
                let result = rebaseSession did since hints
                case result of
                    SessionInvalid _ -> return ()  -- expected
                    other -> expectationFailure
                        ("Expected SessionInvalid, got: " ++ show other)

    describe "E2E: draft commit/discard cleans up hint session" $ do
        it "commit deletes the hint session" $
            withTestRepo $ \(repo, bus) -> do
                uid <- createTestUser repo "eve"
                _ <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [WaiveOvertime (WorkerId 1)]
                publishCommand bus CLI "eve" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                repoSaveHintSession repo did hints cp
                -- Verify session exists
                loaded <- repoLoadHintSession repo did
                loaded `shouldBe` Just (HintSessionRecord hints cp)
                -- The service layer does the cleanup; no caller help needed.
                _ <- Draft.commitDraft repo did "test commit" False
                afterCommit <- repoLoadHintSession repo did
                afterCommit `shouldBe` Nothing

        it "discard deletes the hint session" $
            withTestRepo $ \(repo, bus) -> do
                uid <- createTestUser repo "frank"
                _ <- repoCreateSession repo uid
                did <- createTestDraft repo
                let hints = [ GrantSkill (WorkerId 3) (SkillId 2)
                            , CloseStation (StationId 1) testSlot
                            ]
                publishCommand bus CLI "frank" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                repoSaveHintSession repo did hints cp
                _ <- Draft.discardDraft repo did
                afterDiscard <- repoLoadHintSession repo did
                afterDiscard `shouldBe` Nothing
                -- Verify draft is also gone
                drafts <- Draft.listDrafts repo
                length drafts `shouldBe` 0

        -- One session per draft: whoever saves last is what the draft holds,
        -- and a commit clears it for everyone (ADR 0013).
        it "the draft holds one session, and commit clears it" $
            withTestRepo $ \(repo, bus) -> do
                uidA <- createTestUser repo "grace"
                _ <- createTestUser repo "heidi"
                _ <- repoCreateSession repo uidA
                did <- createTestDraft repo
                publishCommand bus CLI "grace" "station create 1 grill"
                entries <- repoGetAuditLog repo
                let cp = aeId (last entries)
                repoSaveHintSession repo did [WaiveOvertime (WorkerId 1)] cp
                repoSaveHintSession repo did [WaiveOvertime (WorkerId 2)] cp
                held <- repoLoadHintSession repo did
                held `shouldBe` Just (HintSessionRecord [WaiveOvertime (WorkerId 2)] cp)
                _ <- Draft.commitDraft repo did "test commit" False
                afterCommit <- repoLoadHintSession repo did
                afterCommit `shouldBe` Nothing

-- | Helper: a test Slot
testSlot :: Slot
testSlot = Slot (fromGregorian 2026 5 4) (TimeOfDay 9 0 0) 3600

-- | Helper: create a temporary SQLite repo with pub/sub bus for testing.
withTestRepo :: ((Repository, TopicBus CommandEvent) -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-hint-e2e.db"
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

-- | Helper: create a test draft for April 2026. Forced past the freeze line —
-- the fixture dates are fixed and so frozen for any run after them, and this
-- suite is about hints, not the freeze line.
createTestDraft :: Repository -> IO Int
createTestDraft repo = do
    let opts = Draft.defaultCreateDraftOpts { Draft.cdoForce = True }
    result <- Draft.createDraft repo opts (fromGregorian 2026 4 6) (fromGregorian 2026 4 12)
    case result of
        Right did -> return did
        Left err  -> error $ "Failed to create test draft: " ++ show err

