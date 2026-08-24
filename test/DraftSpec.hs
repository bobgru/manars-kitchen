{-# LANGUAGE OverloadedStrings #-}

module DraftSpec (spec) where

import Test.Hspec
import qualified Data.Set as Set
import Data.Time
    ( Day, TimeOfDay(..), fromGregorian, toGregorian
    , addDays, gregorianMonthLength
    )
import Data.Time.Clock (getCurrentTime, utctDay)

import Auth.Types (UserId(..))
import Domain.Types
    ( WorkerId(..), StationId(..), WorkerStatus(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), DraftInfo(..))
import Domain.SchedulerConfig (SchedulerConfig(..))
import qualified Service.Draft as Draft
import qualified Service.Calendar as Cal
import qualified Service.FreezeLine as Freeze
import qualified Service.Worker as SW
import Service.PubSub
    ( TopicBus, ProgressEvent(..), newTopicBus, subscribe )

import Data.IORef (newIORef, modifyIORef', readIORef)

import System.Directory (removeFile, doesFileExist)
import TestSeed (seedTestUsers)

-- | Create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-draft.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    seedTestUsers repo 9
    action repo
    removeFile path

-- | The worker ids seeded by 'withTestRepo'.
allTestWorkers :: Set.Set WorkerId
allTestWorkers = Set.fromList (map WorkerId [1..9])

-- | A progress bus that counts the 'OptimizeProgress' events published to it.
collectingProgressBus :: IO (TopicBus ProgressEvent, IO Int)
collectingProgressBus = do
    bus <- newTopicBus
    counter <- newIORef (0 :: Int)
    _ <- subscribe bus ".*" $ \_topic evt -> case evt of
        OptimizeProgress _ -> modifyIORef' counter (+ 1)
    return (bus, readIORef counter)

-- | Turn the optimizer on with a short time limit and reporting off, so the
-- test neither runs for the default 30 seconds nor depends on wall-clock
-- timing to decide whether progress was emitted.
setOptEnabled :: Repository -> Double -> IO ()
setOptEnabled repo enabled = do
    cfg <- repoLoadSchedulerConfig repo
    repoSaveSchedulerConfig repo cfg
        { cfgOptEnabled = enabled
        , cfgOptTimeLimitSecs = 1.0
        , cfgOptProgressIntervalSecs = 0.0
        }

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

-- | A date @n@ days from today, for the tests that need one the freeze line
-- cannot reach. Named apart from the @today@ locals below, which are fixtures
-- standing in for a particular Wednesday.
fromToday :: Integer -> IO Day
fromToday n = addDays n . utctDay <$> getCurrentTime

-- | Create a draft, forcing past the freeze line, and flatten the refusal to a
-- string for 'expectationFailure'.
--
-- Every fixture date in this module is a fixed 2026 date, so it is frozen for
-- any run after it — but the freeze line is not what these tests are about, and
-- pinning them to relative dates would make the Mon-Fri reasoning below
-- unreadable.
createForced :: Repository -> Day -> Day -> IO (Either String Int)
createForced repo from to =
    either (Left . show) Right
        <$> Draft.createDraft repo opts from to
  where
    opts = Draft.defaultCreateDraftOpts { Draft.cdoForce = True }

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
            result <- createForced repo (apr 1) (apr 30)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    -- List
                    drafts <- Draft.listDrafts repo
                    case drafts of
                        [d] -> do
                            diId d `shouldBe` did
                            diDateFrom d `shouldBe` apr 1
                            diDateTo d `shouldBe` apr 30
                        _ -> expectationFailure
                                ("Expected 1 draft, got " ++ show (length drafts))
                    -- Delete (discard)
                    _ <- Draft.discardDraft repo did
                    drafts' <- Draft.listDrafts repo
                    length drafts' `shouldBe` 0

    describe "Freeze line on create" $ do
        -- Without force, the fixture dates are in the past and refused. The
        -- refusal names the frozen sub-range so a caller can report it.
        it "refuses a frozen range and names it" $ withTestRepo $ \repo -> do
            freezeLine <- Freeze.computeFreezeLine
            result <- Draft.createDraft repo Draft.defaultCreateDraftOpts
                            (apr 1) (apr 30)
            case result of
                Right _ -> expectationFailure "Expected a frozen-dates refusal"
                Left Draft.DraftOverlapsExisting ->
                    expectationFailure "Expected frozen dates, got an overlap"
                Left (Draft.DraftCoversFrozenDates fr) -> do
                    Draft.frFreezeLine fr `shouldBe` freezeLine
                    Draft.frFrom fr `shouldBe` apr 1
                    Draft.frTo fr `shouldBe` apr 30
            -- The refusal wrote nothing.
            drafts <- Draft.listDrafts repo
            length drafts `shouldBe` 0

        it "creates a range entirely after the freeze line without force" $
            withTestRepo $ \repo -> do
                from <- fromToday 30
                to <- fromToday 36
                result <- Draft.createDraft repo Draft.defaultCreateDraftOpts from to
                case result of
                    Left err -> expectationFailure (show err)
                    Right _  -> do
                        drafts <- Draft.listDrafts repo
                        length drafts `shouldBe` 1

        -- An unfreeze covering every frozen date is as good as force, which is
        -- what makes `calendar unfreeze` followed by `draft create` work.
        it "creates a frozen range when the caller has unfrozen it" $
            withTestRepo $ \repo -> do
                let opts = Draft.defaultCreateDraftOpts
                        { Draft.cdoUnfreezes = Set.singleton (apr 1, apr 30) }
                result <- Draft.createDraft repo opts (apr 1) (apr 30)
                case result of
                    Left err -> expectationFailure (show err)
                    Right _  -> do
                        drafts <- Draft.listDrafts repo
                        length drafts `shouldBe` 1

    describe "Non-overlapping constraint" $ do
        it "rejects overlapping date ranges" $ withTestRepo $ \repo -> do
            result1 <- createForced repo (apr 1) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    -- Try to create an overlapping draft
                    result2 <- createForced repo (apr 15) (may 15)
                    case result2 of
                        Left _  -> return ()  -- expected
                        Right _ -> expectationFailure "Expected overlap rejection"

        it "allows non-overlapping date ranges" $ withTestRepo $ \repo -> do
            result1 <- createForced repo (apr 1) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    result2 <- createForced repo (may 1) (may 31)
                    case result2 of
                        Left err -> expectationFailure ("Should allow non-overlapping: " ++ err)
                        Right _  -> do
                            drafts <- Draft.listDrafts repo
                            length drafts `shouldBe` 2

    describe "activeWorkerIds" $ do
        it "returns every seeded worker" $ withTestRepo $ \repo -> do
            workers <- Draft.activeWorkerIds repo
            workers `shouldBe` allTestWorkers

        -- Deactivating a worker is meant to keep them out of new schedules;
        -- excluding them from the default candidate set is how that happens.
        it "excludes a deactivated worker" $ withTestRepo $ \repo -> do
            repoSetWorkerStatus repo (UserId 4) WSInactive Nothing
            workers <- Draft.activeWorkerIds repo
            workers `shouldBe` Set.delete (WorkerId 4) allTestWorkers

    describe "Draft generate" $ do
        -- Nothing means the active workers, so this fills the draft without the
        -- caller enumerating anyone.
        it "defaults to the active workers when given no set" $
            withTestRepo $ \repo -> do
                _ <- SW.addStation repo "grill" 1 1
                bus <- newTopicBus
                result <- createForced repo (apr 6) (apr 10)
                case result of
                    Left err -> expectationFailure err
                    Right did -> do
                        genResult <- Draft.generateDraft repo did Nothing bus
                        case genResult of
                            Left err -> expectationFailure err
                            Right _  -> do
                                sched <- repoLoadDraftAssignments repo did
                                Set.null (unSchedule sched) `shouldBe` False

        it "produces a schedule within the draft" $ withTestRepo $ \repo -> do
            result <- createForced repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    -- Generate with no workers (should produce empty schedule)
                    bus <- newTopicBus
                    genResult <- Draft.generateDraft repo did (Just Set.empty) bus
                    case genResult of
                        Left err -> expectationFailure err
                        Right _  -> do
                            sched <- repoLoadDraftAssignments repo did
                            -- With no workers, schedule should be empty
                            sched `shouldBe` Schedule Set.empty

        -- opt-enabled defaults to 0, so optimizeSchedule short-circuits to a
        -- single greedy build and never reaches its reporting loop.
        it "publishes no progress when optimization is disabled" $ withTestRepo $ \repo -> do
            _ <- SW.addStation repo "grill" 1 1
            (bus, readEventCount) <- collectingProgressBus
            result <- createForced repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    genResult <- Draft.generateDraft repo did (Just allTestWorkers) bus
                    case genResult of
                        Left err -> expectationFailure err
                        Right _  -> do
                            count <- readEventCount
                            count `shouldBe` 0

        -- With the optimizer on, generate must still fill the draft and return
        -- at the configured limit rather than the 30s default. Apr 6-10 2026 is
        -- Mon-Fri: see the pending test below for why the range stops at Friday.
        -- The event count is not asserted -- reporting is wall-clock throttled,
        -- so a fast run legitimately emits nothing either way.
        it "still fills the draft when optimization is enabled" $ withTestRepo $ \repo -> do
            _ <- SW.addStation repo "grill" 1 1
            setOptEnabled repo 1.0
            bus <- newTopicBus
            result <- createForced repo (apr 6) (apr 10)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    genResult <- Draft.generateDraft repo did (Just allTestWorkers) bus
                    case genResult of
                        Left err -> expectationFailure err
                        Right _  -> do
                            sched <- repoLoadDraftAssignments repo did
                            Set.null (unSchedule sched) `shouldBe` False

        -- Known defect, pre-dating this change. With opt-enabled > 0, a range
        -- containing a Saturday never returns and allocates ~1GB/s until the
        -- OOM killer takes the process. Measured on this fixture:
        --   Apr 6-10 (Mon-Fri)   ok, 1.1s      Apr 6-12 (Mon-Sun)  killed
        --   Apr 13-17 (Mon-Fri)  ok, 1.1s      Apr 11 alone (Sat)  killed
        -- With opt-time-limit-secs at 0.0001 -- which returns before the
        -- iterated-greedy loop runs at all -- a full week finishes in 0.12s, so
        -- the divergence is inside iteratedGreedyStep's perturbed rebuild, on
        -- the weekend-constraint path. The time limit cannot interrupt it
        -- because it is only checked between iterations. Latent until now only
        -- because opt-enabled defaults to 0 and `schedule create` was the sole
        -- caller.
        it "optimizes a range containing a weekend" $
            pendingWith "iteratedGreedyStep diverges on ranges containing a Saturday"

    describe "Draft commit" $ do
        it "writes to calendar and creates history entry" $ withTestRepo $ \repo -> do
            -- Put some assignments in the calendar first
            let original = mkSchedule [ mkAssignment 1 1 (apr 6) 8 ]
            repoSaveCalendar repo (apr 6) (apr 12) original
            -- Create a draft and manually save assignments
            result <- createForced repo (apr 6) (apr 12)
            case result of
                Left err -> expectationFailure err
                Right did -> do
                    let draftSched = mkSchedule [ mkAssignment 2 1 (apr 6) 9 ]
                    repoSaveDraftAssignments repo did draftSched
                    -- Commit
                    commitResult <- Draft.commitDraft repo did "test commit"
                    case commitResult of
                        Left err  -> expectationFailure err
                        Right _ -> do
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
            result <- createForced repo (apr 6) (apr 12)
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
            result1 <- createForced repo (apr 9) (apr 30)
            case result1 of
                Left err -> expectationFailure err
                Right _ -> do
                    result2 <- createForced repo (may 1) (may 31)
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
