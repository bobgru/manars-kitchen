module DraftSpec (spec) where

import Test.Hspec
import qualified Data.Set as Set
import Data.Time
    ( Day, TimeOfDay(..), fromGregorian, toGregorian
    , addDays, gregorianMonthLength
    )

import Domain.Types
    ( WorkerId(..), StationId(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), DraftInfo(..))
import qualified Service.Draft as Draft
import qualified Service.Calendar as Cal

import System.Directory (removeFile, doesFileExist)

-- | Create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-draft.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    action repo
    removeFile path

-- Helper to create an assignment
mkAssignment :: Int -> Int -> Day -> Int -> Assignment
mkAssignment wid sid day hour =
    Assignment (WorkerId wid) (StationId sid)
        (Slot day (TimeOfDay hour 0 0) 3600)

-- Helper to create a schedule from a list of assignments
mkSchedule :: [Assignment] -> Schedule
mkSchedule = Schedule . Set.fromList

apr :: Int -> Day
apr d = fromGregorian 2026 4 d

may :: Int -> Day
may d = fromGregorian 2026 5 d

spec :: Spec
spec = do
    -- ---------------------------------------------------------------
    -- Section 5: Seeding logic unit tests
    -- ---------------------------------------------------------------
    describe "mergePinCalendar" $ do
        it "empty calendar returns only pin expansions" $ do
            let calSched = Schedule Set.empty
                pinSched = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 9
                    , mkAssignment 2 1 (apr 6) 10
                    ]
                merged = Draft.mergePinCalendar calSched pinSched
            merged `shouldBe` pinSched

        it "no pins returns only calendar assignments" $ do
            let calSched = mkSchedule
                    [ mkAssignment 1 2 (apr 6) 9
                    , mkAssignment 2 2 (apr 7) 10
                    ]
                pinSched = Schedule Set.empty
                merged = Draft.mergePinCalendar calSched pinSched
            merged `shouldBe` calSched

        it "conflicting pin and calendar returns pin version" $ do
            -- Calendar: Worker 1 at Station 2 on Apr 6 at 9:00
            -- Pin:     Worker 1 at Station 1 on Apr 6 at 9:00
            -- Conflict key: (Worker 1, Apr 6, 9:00) -> pin wins
            let calSched = mkSchedule [ mkAssignment 1 2 (apr 6) 9 ]
                pinSched = mkSchedule [ mkAssignment 1 1 (apr 6) 9 ]
                merged = Draft.mergePinCalendar calSched pinSched
            merged `shouldBe` pinSched

        it "non-conflicting assignments returns union" $ do
            -- Calendar: Worker 1 at Station 2 on Apr 6 at 9:00
            -- Pin:     Worker 2 at Station 1 on Apr 6 at 9:00
            -- No conflict (different workers)
            let calSched = mkSchedule [ mkAssignment 1 2 (apr 6) 9 ]
                pinSched = mkSchedule [ mkAssignment 2 1 (apr 6) 9 ]
                merged = Draft.mergePinCalendar calSched pinSched
                expected = mkSchedule
                    [ mkAssignment 1 2 (apr 6) 9
                    , mkAssignment 2 1 (apr 6) 9
                    ]
            merged `shouldBe` expected

    -- ---------------------------------------------------------------
    -- Section 6: Integration tests
    -- ---------------------------------------------------------------
    describe "Draft create/list/delete round-trip" $ do
        it "creates, lists, and deletes a draft" $ withTestRepo $ \repo -> do
            -- Create
            result <- Draft.createDraft repo (apr 1) (apr 30)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    -- List
                    drafts <- Draft.listDrafts repo
                    length drafts `shouldBe` 1
                    diId (head drafts) `shouldBe` did
                    diDateFrom (head drafts) `shouldBe` apr 1
                    diDateTo (head drafts) `shouldBe` apr 30
                    -- Delete (discard)
                    _ <- Draft.discardDraft repo did
                    drafts' <- Draft.listDrafts repo
                    length drafts' `shouldBe` 0

    describe "Non-overlapping constraint" $ do
        it "rejects overlapping date ranges" $ withTestRepo $ \repo -> do
            result1 <- Draft.createDraft repo (apr 1) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    -- Try to create an overlapping draft
                    result2 <- Draft.createDraft repo (apr 15) (may 15)
                    case result2 of
                        Left _  -> return ()  -- expected
                        Right _ -> expectationFailure "Expected overlap rejection"

        it "allows non-overlapping date ranges" $ withTestRepo $ \repo -> do
            result1 <- Draft.createDraft repo (apr 1) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    result2 <- Draft.createDraft repo (may 1) (may 31)
                    case result2 of
                        Left err -> expectationFailure ("Should allow non-overlapping: " ++ err)
                        Right _  -> do
                            drafts <- Draft.listDrafts repo
                            length drafts `shouldBe` 2

    describe "Draft generate" $ do
        it "produces a schedule within the draft" $ withTestRepo $ \repo -> do
            result <- Draft.createDraft repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    -- Generate with no workers (should produce empty schedule)
                    genResult <- Draft.generateDraft repo did Set.empty
                    case genResult of
                        Left err -> expectationFailure err
                        Right _  -> do
                            sched <- repoLoadDraftAssignments repo did
                            -- With no workers, schedule should be empty
                            sched `shouldBe` Schedule Set.empty

    describe "Draft commit" $ do
        it "writes to calendar and creates history entry" $ withTestRepo $ \repo -> do
            -- Put some assignments in the calendar first
            let original = mkSchedule [ mkAssignment 1 1 (apr 6) 8 ]
            repoSaveCalendar repo (apr 6) (apr 12) original
            -- Create a draft and manually save assignments
            result <- Draft.createDraft repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    let draftSched = mkSchedule [ mkAssignment 2 1 (apr 6) 9 ]
                    repoSaveDraftAssignments repo did draftSched
                    -- Commit
                    commitResult <- Draft.commitDraft repo did "test commit"
                    case commitResult of
                        Left err  -> expectationFailure err
                        Right () -> do
                            -- Calendar should have draft's assignments
                            current <- Cal.loadCalendarSlice repo (apr 6) (apr 12)
                            current `shouldBe` draftSched
                            -- History should have the original
                            commits <- Cal.listCalendarHistory repo
                            length commits `shouldBe` 1
                            -- Draft should be gone
                            drafts <- Draft.listDrafts repo
                            length drafts `shouldBe` 0

    describe "Draft discard" $ do
        it "leaves calendar unchanged" $ withTestRepo $ \repo -> do
            let original = mkSchedule [ mkAssignment 1 1 (apr 6) 8 ]
            repoSaveCalendar repo (apr 6) (apr 12) original
            result <- Draft.createDraft repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    _ <- Draft.discardDraft repo did
                    -- Calendar should be unchanged
                    current <- Cal.loadCalendarSlice repo (apr 6) (apr 12)
                    current `shouldBe` original
                    -- No history commits
                    commits <- Cal.listCalendarHistory repo
                    length commits `shouldBe` 0

    describe "Concurrent drafts" $ do
        it "this-month + next-month can coexist" $ withTestRepo $ \repo -> do
            -- Simulate this-month (Apr 9-30) and next-month (May 1-31)
            result1 <- Draft.createDraft repo (apr 9) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    result2 <- Draft.createDraft repo (may 1) (may 31)
                    case result2 of
                        Left err -> expectationFailure ("Should allow concurrent: " ++ err)
                        Right _  -> do
                            drafts <- Draft.listDrafts repo
                            length drafts `shouldBe` 2

    describe "Date range computation" $ do
        it "this-month: tomorrow through end of month" $ do
            -- Given today = Apr 8, 2026
            let today = apr 8
                (y, m, _) = toGregorian today
                lastDay = fromGregorian y m (gregorianMonthLength y m)
                dateFrom = addDays 1 today
            dateFrom `shouldBe` apr 9
            lastDay `shouldBe` apr 30

        it "next-month: first through last of next month" $ do
            let today = apr 8
                (y, m, _) = toGregorian today
                (ny, nm) = if m == 12 then (y + 1, 1) else (y, m + 1)
                dateFrom = fromGregorian ny nm 1
                dateTo = fromGregorian ny nm (gregorianMonthLength ny nm)
            dateFrom `shouldBe` may 1
            dateTo `shouldBe` may 31

        it "next-month in December wraps to January" $ do
            let today = fromGregorian 2026 12 15
                (y, m, _) = toGregorian today
                (ny, nm) = if m == 12 then (y + 1, 1) else (y, m + 1)
                dateFrom = fromGregorian ny nm 1
                dateTo = fromGregorian ny nm (gregorianMonthLength ny nm)
            dateFrom `shouldBe` fromGregorian 2027 1 1
            dateTo `shouldBe` fromGregorian 2027 1 31
