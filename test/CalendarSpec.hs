module CalendarSpec (spec) where

import Test.Hspec
import qualified Data.Set as Set
import Data.Time (Day, TimeOfDay(..), fromGregorian)

import Domain.Types
    ( WorkerId(..), StationId(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), CalendarCommit(..))
import qualified Service.Calendar as Cal

import System.Directory (removeFile, doesFileExist)

-- | Create a temporary in-memory-like SQLite repo for testing.
-- Uses a temp file that is cleaned up after each test.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-calendar.db"
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

spec :: Spec
spec = do
    describe "Calendar save/load round-trip" $ do
        it "saves and loads assignments for a date range" $ withTestRepo $ \repo -> do
            let sched = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 1 1 (apr 6) 9
                    , mkAssignment 2 2 (apr 7) 10
                    ]
            repoSaveCalendar repo (apr 6) (apr 12) sched
            loaded <- repoLoadCalendar repo (apr 6) (apr 12)
            loaded `shouldBe` sched

        it "returns empty schedule for empty range" $ withTestRepo $ \repo -> do
            loaded <- repoLoadCalendar repo (apr 1) (apr 30)
            loaded `shouldBe` Schedule Set.empty

        it "overwrites existing assignments in date range" $ withTestRepo $ \repo -> do
            let sched1 = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 7) 9
                    ]
                sched2 = mkSchedule
                    [ mkAssignment 3 1 (apr 6) 8
                    ]
            repoSaveCalendar repo (apr 6) (apr 12) sched1
            repoSaveCalendar repo (apr 6) (apr 12) sched2
            loaded <- repoLoadCalendar repo (apr 6) (apr 12)
            loaded `shouldBe` sched2

    describe "History snapshot correctness" $ do
        it "commit creates a snapshot of existing assignments" $ withTestRepo $ \repo -> do
            let existing = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 7) 9
                    ]
            repoSaveCalendar repo (apr 6) (apr 12) existing
            -- Save commit that snapshots the existing assignments
            commitId <- repoSaveCommit repo (apr 6) (apr 12) "test snapshot" existing
            -- Verify the snapshot matches
            snapshot <- repoLoadCommitAssignments repo commitId
            snapshot `shouldBe` existing

        it "snapshot matches pre-overwrite state via service" $ withTestRepo $ \repo -> do
            let original = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 7) 9
                    ]
                replacement = mkSchedule
                    [ mkAssignment 3 1 (apr 6) 10
                    ]
            -- Put original in calendar
            repoSaveCalendar repo (apr 6) (apr 12) original
            -- Commit replacement (which snapshots original first)
            Cal.commitToCalendar repo (apr 6) (apr 12) "replacing" replacement
            -- Calendar should now have the replacement
            current <- repoLoadCalendar repo (apr 6) (apr 12)
            current `shouldBe` replacement
            -- History should have the original
            commits <- repoListCommits repo
            case commits of
                [c] -> do
                    snapshot <- repoLoadCommitAssignments repo (ccId c)
                    snapshot `shouldBe` original
                _ -> expectationFailure
                        ("Expected 1 commit, got " ++ show (length commits))

        it "commit to empty range creates empty snapshot" $ withTestRepo $ \repo -> do
            let newSched = mkSchedule [mkAssignment 1 1 (apr 6) 8]
            Cal.commitToCalendar repo (apr 6) (apr 12) "first commit" newSched
            commits <- repoListCommits repo
            case commits of
                [c] -> do
                    snapshot <- repoLoadCommitAssignments repo (ccId c)
                    snapshot `shouldBe` Schedule Set.empty
                _ -> expectationFailure
                        ("Expected 1 commit, got " ++ show (length commits))

    describe "Date range semantics" $ do
        it "partial overlap overwrites correctly" $ withTestRepo $ \repo -> do
            let sched1 = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8   -- week 1
                    , mkAssignment 2 2 (apr 10) 9  -- week 1
                    , mkAssignment 3 1 (apr 13) 8  -- week 2
                    ]
            -- Save for apr 6-19 (two weeks)
            repoSaveCalendar repo (apr 6) (apr 19) sched1
            -- Now overwrite only apr 13-19 (week 2)
            let sched2 = mkSchedule [mkAssignment 4 1 (apr 15) 10]
            repoSaveCalendar repo (apr 13) (apr 19) sched2
            -- Week 1 should be unchanged
            week1 <- repoLoadCalendar repo (apr 6) (apr 12)
            let expectedWeek1 = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 10) 9
                    ]
            week1 `shouldBe` expectedWeek1
            -- Week 2 should have only the new assignment
            week2 <- repoLoadCalendar repo (apr 13) (apr 19)
            week2 `shouldBe` sched2

        it "sparse assignments clear full range" $ withTestRepo $ \repo -> do
            let dense = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 7) 9
                    , mkAssignment 3 1 (apr 8) 10
                    ]
            repoSaveCalendar repo (apr 6) (apr 12) dense
            -- Commit a sparse schedule (only one day) for the full range
            let sparse = mkSchedule [mkAssignment 4 1 (apr 6) 8]
            repoSaveCalendar repo (apr 6) (apr 12) sparse
            loaded <- repoLoadCalendar repo (apr 6) (apr 12)
            loaded `shouldBe` sparse

    describe "commitToCalendar service" $ do
        it "snapshot-then-overwrite atomicity" $ withTestRepo $ \repo -> do
            -- Start with some existing data
            let original = mkSchedule
                    [ mkAssignment 1 1 (apr 6) 8
                    , mkAssignment 2 2 (apr 7) 9
                    ]
            repoSaveCalendar repo (apr 6) (apr 12) original
            -- Commit twice
            let replacement1 = mkSchedule [mkAssignment 3 1 (apr 6) 10]
            Cal.commitToCalendar repo (apr 6) (apr 12) "commit 1" replacement1
            let replacement2 = mkSchedule [mkAssignment 4 2 (apr 8) 11]
            Cal.commitToCalendar repo (apr 6) (apr 12) "commit 2" replacement2
            -- Calendar should have replacement2
            current <- repoLoadCalendar repo (apr 6) (apr 12)
            current `shouldBe` replacement2
            -- Should have 2 history commits
            commits <- repoListCommits repo
            case commits of
                [latest, oldest] -> do
                    -- Most recent (first in list, reverse chrono) should snapshot replacement1
                    ccNote latest `shouldBe` "commit 2"
                    snapshot2 <- repoLoadCommitAssignments repo (ccId latest)
                    snapshot2 `shouldBe` replacement1
                    -- Oldest commit should snapshot original
                    ccNote oldest `shouldBe` "commit 1"
                    snapshot1 <- repoLoadCommitAssignments repo (ccId oldest)
                    snapshot1 `shouldBe` original
                _ -> expectationFailure
                        ("Expected 2 commits, got " ++ show (length commits))
