module Domain.Worker
    ( -- * Types
      WorkerContext(..)
    , emptyWorkerContext
    , OvertimeModel(..)
    , PayPeriodTracking(..)
      -- * Hours computation
    , slotWeek
    , workerWeeklyHours
    , workerPeriodHours
    , workerMaxHours
    , workerOptedInOvertime
    , wouldBeOvertime
      -- * Employment status queries
    , workerOvertimeModel
    , workerPayPeriodTracking
    , workerIsTemp
      -- * Daily rules
    , workerDailyHours
    , wouldExceedDailyRegular
    , wouldExceedDailyTotal
    , needsBreak
    , violatesRestPeriod
      -- * Seniority
    , workerSeniority
      -- * Cross-training
    , workerCrossTrainingGoals
      -- * Pairing
    , workerAvoidsAt
    , workerPrefersAt
      -- * Preferences
    , workerStationPrefs
    , workerPrefersVariety
    , stationPreferenceRank
    , recentStations
      -- * Assignment attempts
    , tryAssignHours
    , tryAssignOvertimeHours
      -- * Tests
    , spec
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.List (elemIndex)
import Data.Time (Day, TimeOfDay(..), addDays, dayOfWeek, DayOfWeek(..), fromGregorian,
                  timeOfDayToTime)
import Test.Hspec

import Domain.Types
import Domain.Schedule (assign, byWorker, byWorkerSlot, byDay)
import Domain.SchedulerConfig (SchedulerConfig(..), defaultConfig)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | Overtime model for a worker.
data OvertimeModel
    = OTEligible    -- ^ Scheduler auto-assigns overtime
    | OTManualOnly  -- ^ Manager must explicitly accept; never auto-assigned
    | OTExempt      -- ^ Overtime concept doesn't apply (e.g., per-diem)
    deriving (Eq, Ord, Show, Read)

-- | Pay period tracking mode for a worker.
data PayPeriodTracking
    = PPStandard  -- ^ Hours tracked against weekly limit
    | PPExempt    -- ^ No hour limit enforced by scheduler
    deriving (Eq, Ord, Show, Read)

-- | Reference data for worker constraints and preferences.
data WorkerContext = WorkerContext
    { wcMaxPeriodHours :: !(Map WorkerId DiffTime)
      -- ^ Maximum regular (non-overtime) hours per pay period.
      -- Workers not in the map have no hour limit.
    , wcOvertimeOptIn  :: !(Set WorkerId)
      -- ^ Workers who have opted in to overtime availability.
    , wcStationPrefs   :: !(Map WorkerId [StationId])
      -- ^ Ordered station preferences per worker (most preferred first).
      -- Workers not in the map have no preference.
    , wcPrefersVariety :: !(Set WorkerId)
      -- ^ Workers who prefer to rotate among different stations
      -- rather than staying at the same one.
    , wcShiftPrefs    :: !(Map WorkerId [String])
      -- ^ Preferred shift names per worker, e.g. ["morning"], ["afternoon", "weekend"].
      -- "weekend" is a special preference for Saturday/Sunday.
    , wcWeekendOnly  :: !(Set WorkerId)
      -- ^ Workers who work only on weekends. These workers are exempt
      -- from the alternating-weekends-off rule.
    , wcSeniority    :: !(Map WorkerId Int)
      -- ^ Per-worker seniority level (default 1). Higher level allows
      -- more concurrent station assignments during multi-station hours.
    , wcCrossTraining :: !(Map WorkerId (Set SkillId))
      -- ^ Per-worker cross-training goals. A worker with a goal for
      -- skill S can be assigned to stations requiring S (even if
      -- unqualified) when a higher-seniority worker is present.
    , wcAvoidPairing :: !(Map WorkerId (Set WorkerId))
      -- ^ Workers who should NOT be assigned to the same slot.
      -- Symmetric: if A avoids B, B also avoids A.
    , wcPreferPairing :: !(Map WorkerId (Set WorkerId))
      -- ^ Workers who prefer to be assigned to the same slot.
      -- Symmetric: if A prefers B, B also prefers A.
    , wcOvertimeModel :: !(Map WorkerId OvertimeModel)
      -- ^ Per-worker overtime model. Workers not in the map default to OTEligible.
    , wcPayPeriodTracking :: !(Map WorkerId PayPeriodTracking)
      -- ^ Per-worker pay period tracking. Workers not in the map default to PPStandard.
    , wcIsTemp :: !(Set WorkerId)
      -- ^ Workers flagged as temporary. Informational only, no scheduling impact.
    } deriving (Eq, Ord, Show, Read)

emptyWorkerContext :: WorkerContext
emptyWorkerContext = WorkerContext Map.empty Set.empty Map.empty Set.empty Map.empty Set.empty Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty Set.empty

-- ---------------------------------------------------------------------
-- Hours computation
-- ---------------------------------------------------------------------

-- | The ISO week (Monday-Sunday) containing a given day,
-- represented as the Monday of that week.
slotWeek :: Day -> Day
slotWeek d =
    let dow = dayOfWeek d
        offset = case dow of
            Monday    -> 0
            Tuesday   -> 1
            Wednesday -> 2
            Thursday  -> 3
            Friday    -> 4
            Saturday  -> 5
            Sunday    -> 6
    in addDays (negate offset) d

-- | Total hours a worker is assigned during the ISO week containing
-- the given day. Multi-station assignments at the same slot count
-- only once (unique slots, not total assignments).
workerWeeklyHours :: WorkerId -> Day -> Schedule -> DiffTime
workerWeeklyHours w day sched =
    let weekStart = slotWeek day
        weekEnd   = addDays 7 weekStart
        assignments = byWorker w sched
        uniqueSlots = Set.fromList
            [ assignSlot a
            | a <- Set.toList assignments
            , let d = slotDate (assignSlot a)
            , d >= weekStart && d < weekEnd
            ]
    in Set.foldl' (\acc s -> acc + slotDuration s) 0 uniqueSlots

-- | Total hours a worker is assigned during a pay period
-- (from periodStart inclusive to periodEnd exclusive).
-- Multi-station assignments at the same slot count only once.
workerPeriodHours :: WorkerId -> Day -> Day -> Schedule -> DiffTime
workerPeriodHours w periodStart periodEnd sched =
    let assignments = byWorker w sched
        uniqueSlots = Set.fromList
            [ assignSlot a
            | a <- Set.toList assignments
            , let d = slotDate (assignSlot a)
            , d >= periodStart && d < periodEnd
            ]
    in Set.foldl' (\acc s -> acc + slotDuration s) 0 uniqueSlots

-- | Maximum regular hours per pay period for a worker.
-- Returns Nothing if no limit is configured.
workerMaxHours :: WorkerContext -> WorkerId -> Maybe DiffTime
workerMaxHours ctx w = Map.lookup w (wcMaxPeriodHours ctx)

-- | Has a worker opted in to overtime?
workerOptedInOvertime :: WorkerContext -> WorkerId -> Bool
workerOptedInOvertime ctx w = Set.member w (wcOvertimeOptIn ctx)

-- | Overtime model for a worker (default OTEligible).
workerOvertimeModel :: WorkerContext -> WorkerId -> OvertimeModel
workerOvertimeModel ctx w = Map.findWithDefault OTEligible w (wcOvertimeModel ctx)

-- | Pay period tracking for a worker (default PPStandard).
workerPayPeriodTracking :: WorkerContext -> WorkerId -> PayPeriodTracking
workerPayPeriodTracking ctx w = Map.findWithDefault PPStandard w (wcPayPeriodTracking ctx)

-- | Is a worker flagged as temporary?
workerIsTemp :: WorkerContext -> WorkerId -> Bool
workerIsTemp ctx w = Set.member w (wcIsTemp ctx)

-- | Would adding this assignment cause the worker to exceed their
-- regular per-period hours?
-- Returns False if the worker has no hour limit.
-- If the worker is already assigned at this slot (multi-station),
-- the added time is 0.
-- The period bounds and calendar hours are passed in so the scheduler
-- can pre-compute them. For exempt workers, calendarHrs is ignored.
wouldBeOvertime :: WorkerContext -> (Day, Day) -> Map WorkerId DiffTime
               -> Schedule -> Assignment -> Bool
wouldBeOvertime ctx (periodStart, periodEnd) calendarHrs sched a =
    case workerPayPeriodTracking ctx (assignWorker a) of
        PPExempt -> False  -- no hour limit enforced
        PPStandard ->
            case workerMaxHours ctx (assignWorker a) of
                Nothing  -> False
                Just maxH ->
                    let w = assignWorker a
                        draftHrs = workerPeriodHours w periodStart periodEnd sched
                        calHrs = Map.findWithDefault 0 w calendarHrs
                        alreadyAtSlot = not (Set.null (byWorkerSlot w (assignSlot a) sched))
                        added = if alreadyAtSlot then 0 else slotDuration (assignSlot a)
                    in draftHrs + calHrs + added > maxH

-- ---------------------------------------------------------------------
-- Daily rules
-- ---------------------------------------------------------------------

-- Note: daily rule thresholds are now in SchedulerConfig.
-- Helper to extract them as the types needed internally.
maxDailyRegularFromCfg :: SchedulerConfig -> DiffTime
maxDailyRegularFromCfg cfg = fromIntegral (round (cfgMaxDailyRegularHours cfg * 3600) :: Int)

maxDailyTotalFromCfg :: SchedulerConfig -> DiffTime
maxDailyTotalFromCfg cfg = fromIntegral (round (cfgMaxDailyTotalHours cfg * 3600) :: Int)

maxConsecutiveFromCfg :: SchedulerConfig -> Int
maxConsecutiveFromCfg cfg = round (cfgMaxConsecutiveHours cfg)

minRestHoursFromCfg :: SchedulerConfig -> Int
minRestHoursFromCfg cfg = round (cfgMinRestHours cfg)

-- | Total hours a worker is assigned on a given day.
-- Multi-station assignments at the same slot count only once.
workerDailyHours :: WorkerId -> Day -> Schedule -> DiffTime
workerDailyHours w day sched =
    let dayAssignments = Set.filter (\a -> assignWorker a == w) (byDay day sched)
        uniqueSlots = Set.fromList [assignSlot a | a <- Set.toList dayAssignments]
    in Set.foldl' (\acc s -> acc + slotDuration s) 0 uniqueSlots

-- | Would adding this assignment push the worker past regular daily hours?
-- Multi-station adds 0 if already at the slot.
wouldExceedDailyRegular :: SchedulerConfig -> Assignment -> Schedule -> Bool
wouldExceedDailyRegular cfg a sched =
    let current = workerDailyHours (assignWorker a) (slotDate (assignSlot a)) sched
        alreadyAtSlot = not (Set.null (byWorkerSlot (assignWorker a) (assignSlot a) sched))
        added = if alreadyAtSlot then 0 else slotDuration (assignSlot a)
    in current + added > maxDailyRegularFromCfg cfg

-- | Would adding this assignment push the worker past total daily hours
-- (regular + overtime)? Multi-station adds 0 if already at the slot.
wouldExceedDailyTotal :: SchedulerConfig -> Assignment -> Schedule -> Bool
wouldExceedDailyTotal cfg a sched =
    let current = workerDailyHours (assignWorker a) (slotDate (assignSlot a)) sched
        alreadyAtSlot = not (Set.null (byWorkerSlot (assignWorker a) (assignSlot a) sched))
        added = if alreadyAtSlot then 0 else slotDuration (assignSlot a)
    in current + added > maxDailyTotalFromCfg cfg

-- | Does the worker need a mandatory break at this slot?
-- Returns True if they have worked maxConsecutive consecutive hours
-- immediately before this slot (no gap).
needsBreak :: SchedulerConfig -> WorkerId -> Slot -> Schedule -> Bool
needsBreak cfg w slot sched =
    let maxCons = maxConsecutiveFromCfg cfg
        day = slotDate slot
        startTime = timeOfDayToTime (slotStart slot)
        -- All start times for this worker on this day
        dayAssignments = Set.filter (\a -> assignWorker a == w) (byDay day sched)
        startTimes = Set.fromList
            [ timeOfDayToTime (slotStart (assignSlot a)) | a <- Set.toList dayAssignments ]
        -- Walk backwards hour by hour from the current slot
        countBack 0 _ = 0
        countBack n t =
            let prev = t - 3600
            in if Set.member prev startTimes
               then 1 + countBack (n - 1) prev
               else 0
    in countBack maxCons startTime >= maxCons

-- | Would assigning a worker to this slot violate the minimum rest period?
-- Checks that at least minRestHours hours have elapsed since the worker's
-- last assignment on the previous day.
violatesRestPeriod :: SchedulerConfig -> WorkerId -> Slot -> Schedule -> Bool
violatesRestPeriod cfg w slot sched =
    let day = slotDate slot
        prevDay = addDays (-1) day
        prevAssignments = Set.filter (\a -> assignWorker a == w) (byDay prevDay sched)
    in if Set.null prevAssignments
       then False
       else let latestEnd = maximum
                    [ timeOfDayToTime (slotStart (assignSlot a)) + slotDuration (assignSlot a)
                    | a <- Set.toList prevAssignments ]
                -- Gap = time from latest end yesterday to midnight + time from midnight to slot start
                -- = (24h - latestEnd) + slotStart
                midnightSecs = 24 * 3600
                gapSecs = (midnightSecs - latestEnd) + timeOfDayToTime (slotStart slot)
                minRestSecs = fromIntegral (minRestHoursFromCfg cfg) * 3600
            in gapSecs < minRestSecs

-- ---------------------------------------------------------------------
-- Seniority
-- ---------------------------------------------------------------------

-- | Seniority level for a worker (default 1).
-- Higher seniority allows more concurrent station assignments.
workerSeniority :: WorkerContext -> WorkerId -> Int
workerSeniority ctx w = Map.findWithDefault 1 w (wcSeniority ctx)

-- ---------------------------------------------------------------------
-- Cross-training
-- ---------------------------------------------------------------------

-- | Cross-training goals for a worker (empty set = no goals).
workerCrossTrainingGoals :: WorkerContext -> WorkerId -> Set SkillId
workerCrossTrainingGoals ctx w = Map.findWithDefault Set.empty w (wcCrossTraining ctx)

-- ---------------------------------------------------------------------
-- Pairing
-- ---------------------------------------------------------------------

-- | Does the worker have anyone they should avoid at the given slot?
-- Returns True if any worker already assigned at the slot is in this
-- worker's avoid set.
workerAvoidsAt :: WorkerContext -> WorkerId -> Set WorkerId -> Bool
workerAvoidsAt ctx w others =
    let avoidSet = Map.findWithDefault Set.empty w (wcAvoidPairing ctx)
    in not (Set.null (Set.intersection avoidSet others))

-- | How many preferred coworkers are already at the given slot?
workerPrefersAt :: WorkerContext -> WorkerId -> Set WorkerId -> Int
workerPrefersAt ctx w others =
    let prefSet = Map.findWithDefault Set.empty w (wcPreferPairing ctx)
    in Set.size (Set.intersection prefSet others)

-- ---------------------------------------------------------------------
-- Preferences
-- ---------------------------------------------------------------------

-- | A worker's ordered station preferences (most preferred first).
-- Empty list means no preference.
workerStationPrefs :: WorkerContext -> WorkerId -> [StationId]
workerStationPrefs ctx w = Map.findWithDefault [] w (wcStationPrefs ctx)

-- | Does a worker prefer variety?
workerPrefersVariety :: WorkerContext -> WorkerId -> Bool
workerPrefersVariety ctx w = Set.member w (wcPrefersVariety ctx)

-- | Preference rank of a station for a worker.
-- Returns Nothing if the station is not in the worker's preference list.
-- Lower rank = more preferred (0 is most preferred).
stationPreferenceRank :: WorkerContext -> WorkerId -> StationId -> Maybe Int
stationPreferenceRank ctx w st = elemIndex st (workerStationPrefs ctx w)

-- | The set of distinct stations a worker has been assigned to
-- in a given date range (inclusive of start, exclusive of end).
-- Useful for the scheduler to know what stations a worker has
-- recently worked when they prefer variety.
recentStations :: WorkerId -> Day -> Day -> Schedule -> Set StationId
recentStations w startDay endDay sched =
    let assignments = byWorker w sched
    in Set.foldl' (\acc a ->
            let d = slotDate (assignSlot a)
            in if d >= startDay && d < endDay
               then Set.insert (assignStation a) acc
               else acc)
        Set.empty assignments

-- ---------------------------------------------------------------------
-- Assignment attempts
-- ---------------------------------------------------------------------

-- | Attempt an assignment, failing if it would cause overtime.
-- Does not check skills — compose with 'Domain.Skill.tryAssign'
-- for full validation.
tryAssignHours :: WorkerContext -> (Day, Day) -> Map WorkerId DiffTime
              -> Assignment -> Schedule -> Maybe Schedule
tryAssignHours ctx bounds calHrs a sched
    | wouldBeOvertime ctx bounds calHrs sched a = Nothing
    | otherwise                                 = Just (assign a sched)

-- | Attempt an assignment, allowing overtime only if the worker's
-- overtime model permits it. OTEligible workers who opted in get
-- overtime. OTManualOnly workers never get auto-assigned overtime.
-- OTExempt workers skip the overtime concept entirely.
tryAssignOvertimeHours :: WorkerContext -> (Day, Day) -> Map WorkerId DiffTime
                      -> Assignment -> Schedule -> Maybe Schedule
tryAssignOvertimeHours ctx bounds calHrs a sched
    | not (wouldBeOvertime ctx bounds calHrs sched a) = Just (assign a sched)
    | otherwise = case workerOvertimeModel ctx (assignWorker a) of
        OTExempt     -> Just (assign a sched)
        OTManualOnly -> Nothing
        OTEligible   -> if workerOptedInOvertime ctx (assignWorker a)
                        then Just (assign a sched)
                        else Nothing

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

tw_alice, tw_bob, tw_carol :: WorkerId
tw_alice = WorkerId 1  -- 40 hours max, opted in to overtime, prefers grill then prep
tw_bob   = WorkerId 2  -- 20 hours max, not opted in, prefers variety
tw_carol = WorkerId 3  -- no hour limit, no preferences

tst_grill, tst_prep, tst_dish :: StationId
tst_grill = StationId 1
tst_prep  = StationId 2
tst_dish  = StationId 3

testWorkerContext :: WorkerContext
testWorkerContext = WorkerContext
    { wcMaxPeriodHours = Map.fromList
        [ (tw_alice, 40 * 3600)  -- 40 hours in seconds
        , (tw_bob,   20 * 3600)  -- 20 hours
        -- carol: no entry, no limit
        ]
    , wcOvertimeOptIn = Set.singleton tw_alice
    , wcStationPrefs = Map.fromList
        [ (tw_alice, [tst_grill, tst_prep])  -- alice prefers grill, then prep
        , (tw_bob,   [tst_prep, tst_dish])   -- bob prefers prep, then dish
        -- carol: no preferences
        ]
    , wcPrefersVariety = Set.singleton tw_bob
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

-- Monday 2026-05-04 through Sunday 2026-05-10
testTuesday, testFriday, testSaturday, testNextMonday :: Slot
testTuesday    = mkTestSlot (fromGregorian 2026 5 5)  9
testFriday     = mkTestSlot (fromGregorian 2026 5 8)  9
testSaturday   = mkTestSlot (fromGregorian 2026 5 9)  9
testNextMonday = mkTestSlot (fromGregorian 2026 5 11) 9

-- Default period bounds and calendar hours for testing (weekly, covering test week)
testBounds :: (Day, Day)
testBounds = (fromGregorian 2026 5 4, fromGregorian 2026 5 11)

testCalHrs :: Map WorkerId DiffTime
testCalHrs = Map.empty

mkTestSlot :: Day -> Int -> Slot
mkTestSlot d h = Slot d (TimeOfDay h 0 0) 3600

-- | Build a schedule where a worker has n hours on consecutive days
-- starting from Monday.
scheduleWithHours :: WorkerId -> Int -> Schedule
scheduleWithHours w n =
    let days = [fromGregorian 2026 5 (4 + i) | i <- [0..n-1]]
        slots = [Slot d (TimeOfDay 9 0 0) 3600 | d <- days]
    in foldl (\s t -> assign (Assignment w tst_grill t) s) emptySchedule slots

-- | Build a schedule where a worker has the given number of hours
-- on Monday (using consecutive 1-hour slots).
scheduleWithDayHours :: WorkerId -> Int -> Schedule
scheduleWithDayHours w n =
    let slots = [Slot (fromGregorian 2026 5 4) (TimeOfDay (9 + h) 0 0) 3600
                | h <- [0..n - 1]]
    in foldl (\s t -> assign (Assignment w tst_grill t) s) emptySchedule slots

spec :: Spec
spec = do
    describe "slotWeek" $ do
        it "Monday maps to itself" $
            slotWeek (fromGregorian 2026 5 4) `shouldBe` fromGregorian 2026 5 4

        it "Wednesday maps to Monday" $
            slotWeek (fromGregorian 2026 5 6) `shouldBe` fromGregorian 2026 5 4

        it "Sunday maps to Monday of same week" $
            slotWeek (fromGregorian 2026 5 10) `shouldBe` fromGregorian 2026 5 4

        it "next Monday maps to next week" $
            slotWeek (fromGregorian 2026 5 11) `shouldBe` fromGregorian 2026 5 11

        it "fixture dates are in the expected week" $ do
            dayOfWeek (fromGregorian 2026 5 4) `shouldBe` Monday
            dayOfWeek (fromGregorian 2026 5 9) `shouldBe` Saturday

    describe "workerWeeklyHours" $ do
        it "is 0 for empty schedule" $
            workerWeeklyHours tw_alice (fromGregorian 2026 5 4) emptySchedule
                `shouldBe` 0

        it "sums hours within the week" $
            let sched = scheduleWithHours tw_alice 5  -- 5 hours Mon-Fri
            in workerWeeklyHours tw_alice (fromGregorian 2026 5 4) sched
                `shouldBe` 5 * 3600

        it "does not count hours from next week" $
            let sched = assign (Assignment tw_alice tst_grill testNextMonday) emptySchedule
            in workerWeeklyHours tw_alice (fromGregorian 2026 5 4) sched
                `shouldBe` 0

        it "counts Saturday within the same week" $
            let sched = assign (Assignment tw_alice tst_grill testSaturday) emptySchedule
            in workerWeeklyHours tw_alice (fromGregorian 2026 5 4) sched
                `shouldBe` 3600

    describe "workerPeriodHours" $ do
        it "is 0 for empty schedule" $
            workerPeriodHours tw_alice (fromGregorian 2026 5 4) (fromGregorian 2026 5 11) emptySchedule
                `shouldBe` 0

        it "sums hours within period bounds" $
            let sched = scheduleWithHours tw_alice 5  -- 5 hours Mon-Fri
            in workerPeriodHours tw_alice (fromGregorian 2026 5 4) (fromGregorian 2026 5 11) sched
                `shouldBe` 5 * 3600

        it "excludes hours outside period bounds" $
            let sched = assign (Assignment tw_alice tst_grill testNextMonday) emptySchedule
            in workerPeriodHours tw_alice (fromGregorian 2026 5 4) (fromGregorian 2026 5 11) sched
                `shouldBe` 0

        it "includes hours at period start, excludes at period end" $
            let sched = assign (Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 9))
                      $ assign (Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 11) 9))
                        emptySchedule
            in workerPeriodHours tw_alice (fromGregorian 2026 5 4) (fromGregorian 2026 5 11) sched
                `shouldBe` 3600  -- only Monday included, next Monday excluded

    describe "wouldBeOvertime" $ do
        it "is False when well under limit" $
            let sched = scheduleWithHours tw_alice 10  -- 10 of 40 hours
            in wouldBeOvertime testWorkerContext testBounds testCalHrs sched (Assignment tw_alice tst_grill testFriday)
                `shouldBe` False

        it "is True when at limit" $
            let sched = scheduleWithDayHours tw_bob 20  -- bob is at 20 of 20
            in wouldBeOvertime testWorkerContext testBounds testCalHrs sched (Assignment tw_bob tst_grill testTuesday)
                `shouldBe` True

        it "is True when would exceed limit" $
            let sched = scheduleWithDayHours tw_bob 19  -- bob at 19 of 20
                twoHourSlot = Slot (fromGregorian 2026 5 5) (TimeOfDay 9 0 0) 7200
            in wouldBeOvertime testWorkerContext testBounds testCalHrs sched (Assignment tw_bob tst_grill twoHourSlot)
                `shouldBe` True

        it "is False for worker with no limit" $
            let sched = scheduleWithDayHours tw_carol 12
            in wouldBeOvertime testWorkerContext testBounds testCalHrs sched (Assignment tw_carol tst_grill testTuesday)
                `shouldBe` False

    describe "wouldBeOvertime with calendar hours" $ do
        it "includes calendar hours for standard worker" $
            -- bob has 20h limit, 19h in calendar, 0 in draft, +1h slot = 20h total -> not overtime
            let calHrs = Map.singleton tw_bob (19 * 3600)
                a = Assignment tw_bob tst_grill testTuesday
            in wouldBeOvertime testWorkerContext testBounds calHrs emptySchedule a
                `shouldBe` False

        it "calendar hours push standard worker into overtime" $
            -- bob has 20h limit, 19h in calendar, 1h in draft, +1h slot = 21h -> overtime
            let calHrs = Map.singleton tw_bob (19 * 3600)
                sched = scheduleWithHours tw_bob 1
                a = Assignment tw_bob tst_grill testTuesday
            in wouldBeOvertime testWorkerContext testBounds calHrs sched a
                `shouldBe` True

        it "exempt worker ignores calendar hours" $
            -- bob as PPExempt: 20h calendar + 1h slot should not be overtime
            let ctx = testWorkerContext
                    { wcPayPeriodTracking = Map.singleton tw_bob PPExempt }
                calHrs = Map.singleton tw_bob (20 * 3600)
                a = Assignment tw_bob tst_grill testTuesday
            in wouldBeOvertime ctx testBounds calHrs emptySchedule a
                `shouldBe` False

    describe "tryAssignHours (strict, no overtime)" $ do
        it "succeeds when under limit" $
            let sched = scheduleWithHours tw_alice 10
                a = Assignment tw_alice tst_grill testFriday
            in tryAssignHours testWorkerContext testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

        it "fails when would exceed limit" $
            let sched = scheduleWithDayHours tw_bob 20
                a = Assignment tw_bob tst_grill testTuesday
            in tryAssignHours testWorkerContext testBounds testCalHrs a sched
                `shouldBe` Nothing

        it "succeeds for unlimited worker regardless of hours" $
            let sched = scheduleWithDayHours tw_carol 12
                a = Assignment tw_carol tst_grill testTuesday
            in tryAssignHours testWorkerContext testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

    describe "tryAssignOvertimeHours (lenient for opted-in workers)" $ do
        it "succeeds when under limit (same as strict)" $
            let sched = scheduleWithHours tw_alice 10
                a = Assignment tw_alice tst_grill testFriday
            in tryAssignOvertimeHours testWorkerContext testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

        it "succeeds for overtime when worker opted in" $
            let sched = scheduleWithDayHours tw_alice 40  -- at limit
                a = Assignment tw_alice tst_grill testTuesday
            in tryAssignOvertimeHours testWorkerContext testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

        it "fails for overtime when worker not opted in" $
            let sched = scheduleWithDayHours tw_bob 20  -- at limit
                a = Assignment tw_bob tst_grill testTuesday
            in tryAssignOvertimeHours testWorkerContext testBounds testCalHrs a sched
                `shouldBe` Nothing

    describe "Preferences" $ do
        it "workerStationPrefs returns preference list" $
            workerStationPrefs testWorkerContext tw_alice
                `shouldBe` [tst_grill, tst_prep]

        it "workerStationPrefs returns empty for no-preference worker" $
            workerStationPrefs testWorkerContext tw_carol
                `shouldBe` []

        it "workerPrefersVariety" $ do
            workerPrefersVariety testWorkerContext tw_bob `shouldBe` True
            workerPrefersVariety testWorkerContext tw_alice `shouldBe` False

        it "stationPreferenceRank for preferred station" $ do
            stationPreferenceRank testWorkerContext tw_alice tst_grill `shouldBe` Just 0
            stationPreferenceRank testWorkerContext tw_alice tst_prep `shouldBe` Just 1

        it "stationPreferenceRank for non-preferred station" $
            stationPreferenceRank testWorkerContext tw_alice tst_dish `shouldBe` Nothing

        it "recentStations finds stations worked in date range" $
            let sched = assign (Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 9))
                      $ assign (Assignment tw_alice tst_prep  (mkTestSlot (fromGregorian 2026 5 5) 9))
                      $ assign (Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 6) 9))
                        emptySchedule
            in recentStations tw_alice (fromGregorian 2026 5 4) (fromGregorian 2026 5 7) sched
                `shouldBe` Set.fromList [tst_grill, tst_prep]

        it "recentStations excludes dates outside range" $
            let sched = assign (Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 9))
                      $ assign (Assignment tw_alice tst_prep  (mkTestSlot (fromGregorian 2026 5 8) 9))
                        emptySchedule
            in recentStations tw_alice (fromGregorian 2026 5 5) (fromGregorian 2026 5 7) sched
                `shouldBe` Set.empty

    describe "Daily hour limits" $ do
        it "workerDailyHours sums hours on a given day" $
            let sched = scheduleWithDayHours tw_alice 5  -- 5 hours on Monday
            in workerDailyHours tw_alice (fromGregorian 2026 5 4) sched
                `shouldBe` 5 * 3600

        it "workerDailyHours is 0 on a different day" $
            let sched = scheduleWithDayHours tw_alice 5
            in workerDailyHours tw_alice (fromGregorian 2026 5 5) sched
                `shouldBe` 0

        it "wouldExceedDailyRegular is False at 7 hours" $
            let sched = scheduleWithDayHours tw_alice 7
                a = Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 16)
            in wouldExceedDailyRegular defaultConfig a sched `shouldBe` False

        it "wouldExceedDailyRegular is True at 8 hours" $
            let sched = scheduleWithDayHours tw_alice 8
                a = Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 17)
            in wouldExceedDailyRegular defaultConfig a sched `shouldBe` True

        it "wouldExceedDailyTotal is False at 15 hours" $
            -- 15 hours: 0:00 - 14:00
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [0..14]
                a = Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 15)
            in wouldExceedDailyTotal defaultConfig a sched `shouldBe` False

        it "wouldExceedDailyTotal is True at 16 hours" $
            -- 16 hours: 0:00 - 15:00
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [0..15]
                a = Assignment tw_alice tst_grill (mkTestSlot (fromGregorian 2026 5 4) 16)
            in wouldExceedDailyTotal defaultConfig a sched `shouldBe` True

    describe "Mandatory break" $ do
        it "needsBreak is False after 3 consecutive hours" $
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [9, 10, 11]
                slot = mkTestSlot (fromGregorian 2026 5 4) 12
            in needsBreak defaultConfig tw_alice slot sched `shouldBe` False

        it "needsBreak is True after 4 consecutive hours" $
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [9, 10, 11, 12]
                slot = mkTestSlot (fromGregorian 2026 5 4) 13
            in needsBreak defaultConfig tw_alice slot sched `shouldBe` True

        it "needsBreak resets after a gap" $
            -- Work 9-12, break at 13, work 14-17
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [9, 10, 11, 12, 14, 15, 16]
                slot = mkTestSlot (fromGregorian 2026 5 4) 17
            in needsBreak defaultConfig tw_alice slot sched `shouldBe` False

        it "needsBreak is False for a different worker" $
            let sched = foldl (\s h -> assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) h)) s)
                        emptySchedule [9, 10, 11, 12]
                slot = mkTestSlot (fromGregorian 2026 5 4) 13
            in needsBreak defaultConfig tw_bob slot sched `shouldBe` False

    describe "Rest period" $ do
        it "violatesRestPeriod is False with no previous day assignments" $
            let slot = mkTestSlot (fromGregorian 2026 5 5) 6
            in violatesRestPeriod defaultConfig tw_alice slot emptySchedule `shouldBe` False

        it "violatesRestPeriod is False with sufficient gap" $
            -- Worked until 14:00 on Monday, start at 6:00 Tuesday = 16h gap
            let sched = assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) 13)) emptySchedule
                slot = mkTestSlot (fromGregorian 2026 5 5) 6
            in violatesRestPeriod defaultConfig tw_alice slot sched `shouldBe` False

        it "violatesRestPeriod is True with insufficient gap" $
            -- Worked until 20:00 on Monday (slot at 19:00), start at 2:00 Tuesday = 6h gap
            let sched = assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) 19)) emptySchedule
                slot = mkTestSlot (fromGregorian 2026 5 5) 2
            in violatesRestPeriod defaultConfig tw_alice slot sched `shouldBe` True

        it "violatesRestPeriod is True at exactly 7h gap" $
            -- Worked until 20:00 on Monday, start at 3:00 Tuesday = 7h gap < 8h
            let sched = assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) 19)) emptySchedule
                slot = mkTestSlot (fromGregorian 2026 5 5) 3
            in violatesRestPeriod defaultConfig tw_alice slot sched `shouldBe` True

        it "violatesRestPeriod is False at exactly 8h gap" $
            -- Worked until 20:00 on Monday, start at 4:00 Tuesday = 8h gap
            let sched = assign (Assignment tw_alice tst_grill
                            (mkTestSlot (fromGregorian 2026 5 4) 19)) emptySchedule
                slot = mkTestSlot (fromGregorian 2026 5 5) 4
            in violatesRestPeriod defaultConfig tw_alice slot sched `shouldBe` False

    describe "Employment status: wouldBeOvertime with PPExempt" $ do
        it "returns False for PPExempt worker regardless of hours" $
            let ctx = testWorkerContext
                    { wcPayPeriodTracking = Map.singleton tw_bob PPExempt }
                sched = scheduleWithDayHours tw_bob 20  -- bob at limit
                a = Assignment tw_bob tst_grill testTuesday
            in wouldBeOvertime ctx testBounds testCalHrs sched a `shouldBe` False

        it "returns True for PPStandard worker at limit" $
            let sched = scheduleWithDayHours tw_bob 20
                a = Assignment tw_bob tst_grill testTuesday
            in wouldBeOvertime testWorkerContext testBounds testCalHrs sched a `shouldBe` True

        it "PPExempt with no hour limit is still False" $
            let ctx = testWorkerContext
                    { wcPayPeriodTracking = Map.singleton tw_carol PPExempt }
                sched = scheduleWithDayHours tw_carol 12
                a = Assignment tw_carol tst_grill testTuesday
            in wouldBeOvertime ctx testBounds testCalHrs sched a `shouldBe` False

    describe "Employment status: overtime model query functions" $ do
        it "workerOvertimeModel defaults to OTEligible" $
            workerOvertimeModel testWorkerContext tw_alice `shouldBe` OTEligible

        it "workerOvertimeModel returns explicit value" $
            let ctx = testWorkerContext
                    { wcOvertimeModel = Map.singleton tw_alice OTManualOnly }
            in workerOvertimeModel ctx tw_alice `shouldBe` OTManualOnly

        it "workerOvertimeModel OTExempt" $
            let ctx = testWorkerContext
                    { wcOvertimeModel = Map.singleton tw_bob OTExempt }
            in workerOvertimeModel ctx tw_bob `shouldBe` OTExempt

        it "workerPayPeriodTracking defaults to PPStandard" $
            workerPayPeriodTracking testWorkerContext tw_alice `shouldBe` PPStandard

        it "workerPayPeriodTracking returns explicit PPExempt" $
            let ctx = testWorkerContext
                    { wcPayPeriodTracking = Map.singleton tw_alice PPExempt }
            in workerPayPeriodTracking ctx tw_alice `shouldBe` PPExempt

        it "workerIsTemp is False by default" $
            workerIsTemp testWorkerContext tw_alice `shouldBe` False

        it "workerIsTemp returns True when flagged" $
            let ctx = testWorkerContext { wcIsTemp = Set.singleton tw_alice }
            in workerIsTemp ctx tw_alice `shouldBe` True

    describe "Employment status: tryAssignOvertimeHours with overtime model" $ do
        it "OTEligible + opted in allows overtime" $
            let sched = scheduleWithDayHours tw_alice 40  -- at limit
                a = Assignment tw_alice tst_grill testTuesday
            in tryAssignOvertimeHours testWorkerContext testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

        it "OTEligible + not opted in rejects overtime" $
            let ctx = testWorkerContext
                    { wcOvertimeOptIn = Set.empty }  -- alice no longer opted in
                sched = scheduleWithDayHours tw_alice 40
                a = Assignment tw_alice tst_grill testTuesday
            in tryAssignOvertimeHours ctx testBounds testCalHrs a sched `shouldBe` Nothing

        it "OTManualOnly rejects overtime even if opted in" $
            let ctx = testWorkerContext
                    { wcOvertimeModel = Map.singleton tw_alice OTManualOnly
                    , wcOvertimeOptIn = Set.singleton tw_alice }
                sched = scheduleWithDayHours tw_alice 40
                a = Assignment tw_alice tst_grill testTuesday
            in tryAssignOvertimeHours ctx testBounds testCalHrs a sched `shouldBe` Nothing

        it "OTExempt allows assignment regardless of hours" $
            let ctx = testWorkerContext
                    { wcOvertimeModel = Map.singleton tw_alice OTExempt }
                sched = scheduleWithDayHours tw_alice 40
                a = Assignment tw_alice tst_grill testTuesday
            in tryAssignOvertimeHours ctx testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))

        it "under limit succeeds for all models" $
            let ctx = testWorkerContext
                    { wcOvertimeModel = Map.singleton tw_alice OTManualOnly }
                sched = scheduleWithHours tw_alice 10  -- well under limit
                a = Assignment tw_alice tst_grill testFriday
            in tryAssignOvertimeHours ctx testBounds testCalHrs a sched
                `shouldSatisfy` (== Just (assign a sched))
