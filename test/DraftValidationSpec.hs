module DraftValidationSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, TimeOfDay(..), fromGregorian)

import Domain.Types
    ( WorkerId(..), StationId(..), SkillId(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler (SchedulerContext(..))
import Domain.Skill (SkillContext(..))
import Domain.Worker (WorkerContext(..))
import Domain.Absence (emptyAbsenceContext)
import Domain.SchedulerConfig (defaultConfig)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..))
import Service.DraftValidation
    ( DraftViolation(..)
    , validateAssignment, buildLookBackContext
    , validateDraftAgainstCalendar
    )
import qualified Service.Calendar as Cal
import qualified Service.Draft as Draft

import System.Directory (removeFile, doesFileExist)
import Control.Concurrent (threadDelay)  -- for timestamp separation

-- | Create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-draft-validation.db"
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

mkSchedule :: [Assignment] -> Schedule
mkSchedule = Schedule . Set.fromList

apr :: Int -> Day
apr d = fromGregorian 2026 4 d

may :: Int -> Day
may d = fromGregorian 2026 5 d

-- Workers
w_marco, w_lucia, w_carol :: WorkerId
w_marco = WorkerId 5
w_lucia = WorkerId 8
w_carol = WorkerId 3

-- Stations
st_grill, st_prep :: StationId
st_grill = StationId 1
st_prep  = StationId 2

-- Skills
sk_cooking, sk_prep :: SkillId
sk_cooking = SkillId 2
sk_prep    = SkillId 1

-- | Basic skill context: grill requires cooking, prep requires prep.
testSkillCtx :: SkillContext
testSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (w_marco, Set.singleton sk_cooking)
        , (w_lucia, Set.singleton sk_cooking)
        , (w_carol, Set.singleton sk_prep)
        ]
    , scStationRequires = Map.fromList
        [ (st_grill, Set.singleton sk_cooking)
        , (st_prep,  Set.singleton sk_prep)
        ]
    , scSkillImplies = Map.fromList
        [ (sk_cooking, Set.singleton sk_prep)
        ]
    , scAllStations = Set.fromList [st_grill, st_prep]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

-- | Worker context: generous hours.
testWorkerCtx :: WorkerContext
testWorkerCtx = WorkerContext
    { wcMaxWeeklyHours = Map.fromList
        [ (w_marco, 40 * 3600)
        , (w_lucia, 40 * 3600)
        , (w_carol, 40 * 3600)
        ]
    , wcOvertimeOptIn = Set.empty
    , wcStationPrefs  = Map.empty
    , wcPrefersVariety = Set.empty
    , wcShiftPrefs = Map.empty
    , wcWeekendOnly = Set.empty
    , wcSeniority = Map.empty
    , wcCrossTraining = Map.empty
    , wcAvoidPairing = Map.empty
    , wcPreferPairing = Map.empty
    , wcOvertimeModel = Map.empty
    , wcPayPeriodTracking = Map.empty
    , wcIsTemp = Set.empty
    }

-- | Build a SchedulerContext for validation tests.
mkValidationCtx :: Set.Set WorkerId -> SchedulerContext
mkValidationCtx prevWeekendWorkers = SchedulerContext
    { schSkillCtx    = testSkillCtx
    , schWorkerCtx   = testWorkerCtx
    , schAbsenceCtx  = emptyAbsenceContext
    , schSlots       = []
    , schWorkers     = Set.empty
    , schClosedSlots = Set.empty
    , schShifts      = []
    , schPrevWeekendWorkers = prevWeekendWorkers
    , schConfig      = defaultConfig
    }

spec :: Spec
spec = do
    -- ---------------------------------------------------------------
    -- Unit tests for validateAssignment
    -- ---------------------------------------------------------------
    describe "validateAssignment" $ do
        it "detects alternating-weekend violation from look-back" $ do
            -- Marco worked Apr 25-26 weekend (Sat-Sun) in calendar
            let lookBackSched = mkSchedule
                    [ mkAssignment 5 1 (apr 25) 9   -- Marco, Sat Apr 25
                    , mkAssignment 5 1 (apr 26) 9   -- Marco, Sun Apr 26
                    ]
                prevWeekend = buildLookBackContext lookBackSched
                ctx = mkValidationCtx prevWeekend
                -- Marco assigned to May 2 (Saturday) in draft
                draftAssign = mkAssignment 5 1 (may 2) 9
                combined = mkSchedule
                    [ mkAssignment 5 1 (apr 25) 9
                    , mkAssignment 5 1 (apr 26) 9
                    , draftAssign
                    ]
            -- Marco should be in prevWeekendWorkers
            Set.member w_marco prevWeekend `shouldBe` True
            -- Validation should detect alternating weekend violation
            case validateAssignment ctx draftAssign combined of
                Nothing -> expectationFailure "Expected alternating weekend violation"
                Just v  -> dvConstraint v `shouldBe` "alternating weekends"

        it "detects rest-period violation using look-back" $ do
            -- Lucia worked until 22:00 on Apr 30 in calendar
            let lookBackAssign = Assignment w_lucia st_grill
                    (Slot (apr 30) (TimeOfDay 21 0 0) 3600)  -- 21:00-22:00
                -- Lucia assigned at 06:00 on May 1 in draft (only 8h gap)
                draftAssign = Assignment w_lucia st_grill
                    (Slot (may 1) (TimeOfDay 5 0 0) 3600)  -- 05:00 -> 7h gap < 8h min rest
                combined = Schedule (Set.fromList [lookBackAssign, draftAssign])
                ctx = mkValidationCtx Set.empty
            case validateAssignment ctx draftAssign combined of
                Nothing -> expectationFailure "Expected rest period violation"
                Just v  -> dvConstraint v `shouldBe` "rest period"

        it "passes when no constraints are violated" $ do
            let ctx = mkValidationCtx Set.empty
                -- Marco assigned to Monday grill at 9am — no issues
                draftAssign = mkAssignment 5 1 (may 4) 9  -- Monday
                combined = mkSchedule [draftAssign]
            validateAssignment ctx draftAssign combined `shouldBe` Nothing

    -- ---------------------------------------------------------------
    -- Unit tests for buildLookBackContext
    -- ---------------------------------------------------------------
    describe "buildLookBackContext" $ do
        it "extracts weekend workers from schedule" $ do
            let sched = mkSchedule
                    [ mkAssignment 5 1 (apr 25) 9   -- Saturday
                    , mkAssignment 5 1 (apr 26) 9   -- Sunday
                    , mkAssignment 8 1 (apr 24) 9   -- Friday (not weekend)
                    ]
            buildLookBackContext sched `shouldBe` Set.singleton w_marco

        it "returns empty for weekday-only schedule" $ do
            let sched = mkSchedule
                    [ mkAssignment 5 1 (apr 27) 9   -- Monday
                    , mkAssignment 8 1 (apr 28) 9   -- Tuesday
                    ]
            buildLookBackContext sched `shouldBe` Set.empty

    -- ---------------------------------------------------------------
    -- Integration tests for validateDraftAgainstCalendar
    -- ---------------------------------------------------------------
    describe "validateDraftAgainstCalendar" $ do
        it "returns empty when calendar has not changed since draft creation" $
            withTestRepo $ \repo -> do
                -- Create a draft (no calendar changes)
                result <- Draft.createDraft repo (may 1) (may 31)
                case result of
                    Left err -> expectationFailure err
                    Right did -> do
                        violations <- validateDraftAgainstCalendar repo did
                        violations `shouldBe` []

        it "removes violating assignments and returns violations when calendar changed" $
            withTestRepo $ \repo -> do
                -- Create a May draft
                result <- Draft.createDraft repo (may 1) (may 31)
                case result of
                    Left err -> expectationFailure err
                    Right did -> do
                        -- Add Marco's May 2 (Sat) and May 3 (Sun) grill assignments to draft
                        let draftSched = mkSchedule
                                [ mkAssignment 5 1 (may 2) 9    -- Marco, Sat
                                , mkAssignment 5 1 (may 3) 9    -- Marco, Sun
                                , mkAssignment 8 1 (may 4) 9    -- Lucia, Mon (should stay)
                                ]
                        repoSaveDraftAssignments repo did draftSched

                        -- Now commit calendar changes: Marco worked Apr 25-26 weekend
                        let calSched = mkSchedule
                                [ mkAssignment 5 1 (apr 25) 9   -- Marco, Sat
                                , mkAssignment 5 1 (apr 26) 9   -- Marco, Sun
                                ]
                        -- Need a tiny delay so committed_at > draft's last_validated_at
                        threadDelay 10000  -- 10ms: ensure committed_at > last_validated_at
                        Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" calSched

                        -- Validate the draft
                        violations <- validateDraftAgainstCalendar repo did
                        -- Should have violations for Marco's weekend assignments
                        length violations `shouldSatisfy` (>= 1)
                        all (\v -> assignWorker (dvAssignment v) == w_marco) violations
                            `shouldBe` True
                        all (\v -> dvConstraint v == "alternating weekends") violations
                            `shouldBe` True

                        -- Lucia's Monday assignment should still be in the draft
                        updatedSched <- repoLoadDraftAssignments repo did
                        let remaining = Set.toList (unSchedule updatedSched)
                        any (\a -> assignWorker a == w_lucia) remaining
                            `shouldBe` True
                        -- Marco's weekend assignments should be gone
                        any (\a -> assignWorker a == w_marco) remaining
                            `shouldBe` False

        it "returns empty on second call when no further calendar changes" $
            withTestRepo $ \repo -> do
                result <- Draft.createDraft repo (may 1) (may 31)
                case result of
                    Left err -> expectationFailure err
                    Right did -> do
                        let draftSched = mkSchedule
                                [ mkAssignment 5 1 (may 2) 9
                                , mkAssignment 5 1 (may 3) 9
                                ]
                        repoSaveDraftAssignments repo did draftSched

                        let calSched = mkSchedule
                                [ mkAssignment 5 1 (apr 25) 9
                                , mkAssignment 5 1 (apr 26) 9
                                ]
                        threadDelay 1100000
                        Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" calSched

                        -- First call: should detect violations
                        violations1 <- validateDraftAgainstCalendar repo did
                        length violations1 `shouldSatisfy` (>= 1)

                        -- Second call: no further calendar changes, should return empty
                        violations2 <- validateDraftAgainstCalendar repo did
                        violations2 `shouldBe` []
