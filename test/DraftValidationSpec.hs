{-# LANGUAGE OverloadedStrings #-}

module DraftValidationSpec (spec) where

import Test.Hspec
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, TimeOfDay(..), fromGregorian)

import Domain.Types
    ( WorkerId(..), StationId(..), SkillId(..), AbsenceTypeId(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler (SchedulerContext(..))
import Domain.Skill (SkillContext(..))
import Domain.Worker (WorkerContext(..))
import Domain.Absence
    ( AbsenceContext(..), AbsenceType(..)
    , emptyAbsenceContext, requestAbsence, approveAbsence
    )
import Domain.SchedulerConfig (defaultConfig)
import Repo.SQLite (mkSQLiteRepo)
import Repo.Types (Repository(..), DraftInfo, CalendarCommit(..))
import Service.DraftValidation
    ( DraftViolation(..)
    , validateAssignment, buildLookBackContext, validateSchedule
    , computeDraftViolations, pruneDraftViolations, isDraftStale
    , calendarReplacedUnder
    )
import qualified Service.Calendar as Cal
import qualified Service.Draft as Draft

import System.Directory (removeFile, doesFileExist)
import Control.Concurrent (threadDelay)  -- for timestamp separation
import TestSeed (seedTestUsers)

-- | Create a temporary SQLite repo for testing.
withTestRepo :: (Repository -> IO ()) -> IO ()
withTestRepo action = do
    let path = "/tmp/manars-kitchen-test-draft-validation.db"
    exists <- doesFileExist path
    if exists then removeFile path else return ()
    (_, repo) <- mkSQLiteRepo path
    seedTestUsers repo 9
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

-- | Create a draft, forcing past the freeze line, and flatten the refusal to a
-- string for 'expectationFailure'. The fixture dates are fixed 2026 dates and
-- so frozen for any run after them; the alternating-weekend reasoning these
-- tests depend on would be unreadable with dates relative to today.
createForced :: Repository -> Day -> Day -> IO (Either String Int)
createForced repo from to =
    either (Left . show) Right
        <$> Draft.createDraft repo forcedOpts from to

-- | Create options that ignore the freeze line, for the fixed 2026 fixtures.
forcedOpts :: Draft.CreateDraftOpts
forcedOpts = Draft.defaultCreateDraftOpts { Draft.cdoForce = True }

-- | Create a forced draft and hand the action both its id and its loaded
-- 'DraftInfo' — 'isDraftStale' takes the record, not the id.
withDraft :: Repository -> Day -> Day -> (Int -> DraftInfo -> IO ()) -> IO ()
withDraft repo from to action = do
    result <- createForced repo from to
    case result of
        Left err  -> expectationFailure err
        Right did -> do
            mDraft <- repoGetDraft repo did
            case mDraft of
                Nothing    -> expectationFailure
                    ("draft " ++ show did ++ " not found after creation")
                Just draft -> action did draft

-- | An absence context holding one approved single-day absence. Saving this
-- invalidates any draft assignment for that worker on that day *without*
-- committing anything to the calendar — which is exactly the situation that
-- separates 'computeDraftViolations' from 'pruneDraftViolations'.
absenceFor :: WorkerId -> Day -> AbsenceContext
absenceFor w day =
    let atype = AbsenceTypeId 1
        ctx0  = emptyAbsenceContext
            { acTypes = Map.singleton atype (AbsenceType "vacation" False) }
        (ctx1, aid) = requestAbsence w atype day day ctx0
    in case approveAbsence aid ctx1 of
        Just ctx2 -> ctx2
        Nothing   -> error "absenceFor: could not approve the absence"

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
    { wcMaxPeriodHours = Map.fromList
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
    , schPeriodBounds = (fromGregorian 2026 5 4, fromGregorian 2026 5 11)
    , schCalendarHours = Map.empty
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

        -- The demo's "last resort" admin: `worker set-hours admin 0` plus
        -- `worker set-overtime admin on`. The scheduler assigns them precisely
        -- because the opt-in authorises it, and the validator used to call every
        -- one of those assignments a hard-constraint violation, because
        -- `wouldBeOvertime` knows nothing about overtime models or opt-ins.
        it "permits authorised overtime past a zero-hour cap" $ do
            let base = mkValidationCtx Set.empty
                wctx = (schWorkerCtx base)
                    { wcMaxPeriodHours = Map.singleton w_marco 0
                    , wcOvertimeOptIn  = Set.singleton w_marco
                    }
                ctx = base { schWorkerCtx = wctx }
                draftAssign = mkAssignment 5 1 (may 4) 9  -- Monday
                combined = mkSchedule [draftAssign]
            validateAssignment ctx draftAssign combined `shouldBe` Nothing

        it "reports unauthorised overtime past a zero-hour cap" $ do
            let base = mkValidationCtx Set.empty
                wctx = (schWorkerCtx base)
                    { wcMaxPeriodHours = Map.singleton w_marco 0
                    , wcOvertimeOptIn  = Set.empty
                    }
                ctx = base { schWorkerCtx = wctx }
                draftAssign = mkAssignment 5 1 (may 4) 9
                combined = mkSchedule [draftAssign]
            case validateAssignment ctx draftAssign combined of
                Nothing -> expectationFailure "Expected a period-hours violation"
                Just v  -> dvConstraint v `shouldBe` "period hours"

        -- The daily rule had the same shape of bug: the validator applied the
        -- 8-hour regular threshold where the scheduler's overtime pass applies
        -- the 16-hour ceiling, so a legal 9-hour overtime day was a violation.
        it "permits a nine-hour day, which is overtime and not a breach" $ do
            let ctx = mkValidationCtx Set.empty
                -- Nine hours in three-hour blocks: the four-hour consecutive
                -- limit is a separate rule and would otherwise fire first.
                dayAssigns =
                    [ mkAssignment 5 1 (may 4) h | h <- [6, 7, 8, 10, 11, 12, 14, 15, 16] ]
                combined = mkSchedule dayAssigns
            length dayAssigns `shouldBe` 9
            validateAssignment ctx (last dayAssigns) combined `shouldBe` Nothing

    -- ---------------------------------------------------------------
    -- Unit tests for buildLookBackContext
    -- ---------------------------------------------------------------
    -- ---------------------------------------------------------------
    -- The generalised core: a Schedule plus a range, no draft involved.
    -- This is what lets the calendar be validated as ADR 0004's virtual
    -- default draft.
    -- ---------------------------------------------------------------
    describe "validateSchedule" $ do
        it "judges a bare schedule with no draft row anywhere" $
            withTestRepo $ \repo -> do
                let (from, to) = (may 4, may 8)   -- Mon-Fri
                    sched = mkSchedule [mkAssignment 5 1 (may 4) 9]
                violations <- validateSchedule repo (from, to) sched
                violations `shouldBe` []

        it "returns no violations for an empty schedule" $
            withTestRepo $ \repo -> do
                violations <- validateSchedule repo (may 4, may 8) (Schedule Set.empty)
                violations `shouldBe` []

        it "reports a violation in a bare schedule, against real repo state" $
            withTestRepo $ \repo -> do
                -- An approved absence invalidates the assignment without any
                -- draft or calendar commit being involved. This is the sick-call
                -- case ADR 0004 is built around.
                repoSaveAbsenceCtx repo (absenceFor w_marco (may 4))
                let sched = mkSchedule [mkAssignment 5 1 (may 4) 9]
                violations <- validateSchedule repo (may 4, may 8) sched
                map dvConstraint violations `shouldBe` ["absence conflict"]

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
    -- Integration tests for pruneDraftViolations
    -- ---------------------------------------------------------------
    describe "pruneDraftViolations" $ do
        it "returns empty when calendar has not changed since draft creation" $
            withTestRepo $ \repo -> do
                -- Create a draft (no calendar changes)
                result <- createForced repo (may 1) (may 31)
                case result of
                    Left err -> expectationFailure err
                    Right did -> do
                        violations <- pruneDraftViolations repo did
                        violations `shouldBe` []

        it "removes violating assignments and returns violations when calendar changed" $
            withTestRepo $ \repo -> do
                -- Create a May draft
                result <- createForced repo (may 1) (may 31)
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
                        Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" Nothing calSched

                        -- Validate the draft
                        violations <- pruneDraftViolations repo did
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
                result <- createForced repo (may 1) (may 31)
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
                        Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" Nothing calSched

                        -- First call: should detect violations
                        violations1 <- pruneDraftViolations repo did
                        length violations1 `shouldSatisfy` (>= 1)

                        -- Second call: no further calendar changes, should return empty
                        violations2 <- pruneDraftViolations repo did
                        violations2 `shouldBe` []

    -- ---------------------------------------------------------------
    -- isDraftStale: the gate, on its own
    -- ---------------------------------------------------------------
    describe "isDraftStale" $ do
        it "is False when no calendar commit has landed since the draft" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft ->
                    isDraftStale repo draft `shouldReturn` False

        it "is True once a calendar commit lands after the draft" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft -> do
                    threadDelay 1100000  -- committed_at > last_validated_at
                    Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" Nothing
                        (mkSchedule [mkAssignment 5 1 (apr 25) 9])
                    isDraftStale repo draft `shouldReturn` True

    -- ---------------------------------------------------------------
    -- calendarReplacedUnder: the blind spot the staleness gate has, now
    -- that two drafts may cover the same week
    -- ---------------------------------------------------------------
    describe "calendarReplacedUnder" $ do
        it "is empty when nothing has been committed" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft ->
                    calendarReplacedUnder repo draft `shouldReturn` []

        -- The commit that makes a draft *stale* is not necessarily one that
        -- replaced the calendar underneath it: staleness is any commit at all.
        it "ignores a commit outside the draft's own date range" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft -> do
                    threadDelay 1100000
                    Cal.commitToCalendar repo (apr 25) (apr 26) "April weekend" Nothing
                        (mkSchedule [mkAssignment 5 1 (apr 25) 9])
                    -- Stale, but not replaced under: the two questions differ.
                    isDraftStale repo draft `shouldReturn` True
                    calendarReplacedUnder repo draft `shouldReturn` []

        it "names the draft that replaced the calendar under this one" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft -> do
                    threadDelay 1100000
                    -- A sibling draft over part of the same range is committed.
                    Right sibling <- Draft.createDraft repo forcedOpts (may 4) (may 8)
                    repoSaveDraftAssignments repo sibling
                        (mkSchedule [mkAssignment 8 1 (may 4) 9])
                    Right _ <- Draft.commitDraft repo sibling "sibling wins" True
                    replaced <- calendarReplacedUnder repo draft
                    map ccDraftId replaced `shouldBe` [Just sibling]
                    map ccDateFrom replaced `shouldBe` [may 4]

        -- A commit that did not come from a draft still has to be reported, it
        -- just cannot be attributed to one.
        it "reports a draft-less commit with no draft id" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \_ draft -> do
                    threadDelay 1100000
                    Cal.commitToCalendar repo (may 4) (may 8) "by hand" Nothing
                        (mkSchedule [mkAssignment 8 1 (may 4) 9])
                    replaced <- calendarReplacedUnder repo draft
                    map ccDraftId replaced `shouldBe` [Nothing]

    -- ---------------------------------------------------------------
    -- computeDraftViolations: the read half of the split. No staleness
    -- gate, no writes.
    -- ---------------------------------------------------------------
    describe "computeDraftViolations" $ do
        it "reports violations on a draft the calendar has not moved under" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \did draft -> do
                    repoSaveDraftAssignments repo did
                        (mkSchedule [mkAssignment 5 1 (may 2) 9])
                    -- Marco is now on approved absence on May 2. No calendar
                    -- commit, so the draft is not stale.
                    repoSaveAbsenceCtx repo (absenceFor w_marco (may 2))
                    isDraftStale repo draft `shouldReturn` False

                    -- The gated path therefore sees nothing at all...
                    pruneDraftViolations repo did `shouldReturn` []

                    -- ...while the read reports the violation.
                    violations <- computeDraftViolations repo did
                    map dvConstraint violations `shouldBe` ["absence conflict"]
                    map (assignWorker . dvAssignment) violations
                        `shouldBe` [w_marco]

        it "does not remove the assignments it reports" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \did _ -> do
                    let draftSched = mkSchedule
                            [ mkAssignment 5 1 (may 2) 9    -- Marco, will violate
                            , mkAssignment 8 1 (may 4) 9    -- Lucia, will not
                            ]
                    repoSaveDraftAssignments repo did draftSched
                    repoSaveAbsenceCtx repo (absenceFor w_marco (may 2))

                    violations1 <- computeDraftViolations repo did
                    length violations1 `shouldBe` 1

                    -- The draft is untouched: both assignments still there.
                    afterSched <- repoLoadDraftAssignments repo did
                    afterSched `shouldBe` draftSched

                    -- And nothing was consumed — a second call reports the same
                    -- violation, so last_validated_at was not bumped either.
                    violations2 <- computeDraftViolations repo did
                    violations2 `shouldBe` violations1

        it "returns empty for a draft with no assignments" $
            withTestRepo $ \repo ->
                withDraft repo (may 1) (may 31) $ \did _ ->
                    computeDraftViolations repo did `shouldReturn` []

        it "returns empty for a draft that does not exist" $
            withTestRepo $ \repo ->
                computeDraftViolations repo 9999 `shouldReturn` []
