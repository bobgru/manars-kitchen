{-# LANGUAGE BangPatterns #-}
module Domain.Optimizer
    ( -- * Types
      OptProgress(..)
    , OptPhase(..)
      -- * Whole-schedule scoring
    , scoreSchedule
      -- * Neighborhood operations (Phase 1: hard constraints)
    , neighborhoodOf
    , destroyNeighborhood
    , iteratedGreedyStep
      -- * Local search moves (Phase 2: soft constraints)
    , trySwap
    , proposeSwaps
    , hillClimbStep
      -- * Tests
    , spec
    ) where

import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

import Test.Hspec

import Domain.Types
import Domain.Schedule (assign, unassign)
import Domain.Scheduler
    ( SchedulerContext(..), ScheduleResult(..), Unfilled(..), UnfilledKind(..)
    , GreedyStrategy(..)
    , buildScheduleFromPerturbed
    , scoreSlotWorker, canAssignSlot
    )
import Domain.SchedulerConfig (SchedulerConfig(..), defaultConfig)
import Domain.Skill (SkillContext(..))
import Domain.Worker hiding (spec)
import Domain.Absence (emptyAbsenceContext)

import Data.Time (Day, TimeOfDay(..), fromGregorian)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

data OptPhase = PhaseHard | PhaseSoft
    deriving (Eq, Show)

-- | Progress report emitted periodically during optimization.
data OptProgress = OptProgress
    { opIteration   :: !Int
    , opBestUnfilled :: !Int
    , opBestScore   :: !Double
    , opElapsedSecs :: !Double
    , opPhase       :: !OptPhase
    } deriving (Show)

-- ---------------------------------------------------------------------
-- Whole-schedule scoring
-- ---------------------------------------------------------------------

-- | Compute the total soft score for a schedule by summing per-assignment
-- slot-level scores. Higher is better.
scoreSchedule :: SchedulerContext -> Schedule -> Double
scoreSchedule ctx (Schedule assignments) =
    Set.foldl' (\acc a ->
        acc + scoreSlotWorker ctx (assignSlot a) (assignStation a)
                              (Schedule assignments) (assignWorker a)
    ) 0.0 assignments

-- ---------------------------------------------------------------------
-- Neighborhood operations (Phase 1: hard constraints)
-- ---------------------------------------------------------------------

-- | Find the set of existing assignments that are "near" unfilled positions.
-- These are candidates for removal during neighborhood destruction.
-- "Near" means: assignments at the same slot as an unfilled position,
-- plus assignments for the same workers at other slots on the same day.
neighborhoodOf :: SchedulerContext -> [Unfilled] -> Schedule -> Set Assignment
neighborhoodOf _ctx unfilled (Schedule assignments) =
    let -- Slots with unfilled positions
        unfilledSlots = Set.fromList [unfilledSlot u | u <- unfilled]
        -- Assignments at unfilled slots (any station)
        atUnfilledSlots = Set.filter (\a -> Set.member (assignSlot a) unfilledSlots) assignments
        -- Workers involved in those assignments
        involvedWorkers = Set.map assignWorker atUnfilledSlots
        -- Days with unfilled positions
        unfilledDays = Set.map slotDate unfilledSlots
        -- All assignments for those workers on those days
        sameWorkerSameDay = Set.filter (\a ->
            Set.member (assignWorker a) involvedWorkers
            && Set.member (slotDate (assignSlot a)) unfilledDays
            ) assignments
    in Set.union atUnfilledSlots sameWorkerSameDay

-- | Randomly remove a subset of assignments from the neighborhood.
-- Each assignment is removed with probability proportional to @ratio@.
-- The @[Double]@ values (in [0,1)) drive the random decisions.
destroyNeighborhood :: Double -> [Double] -> Set Assignment -> Schedule -> Schedule
destroyNeighborhood ratio randoms neighborhood (Schedule assignments) =
    let toRemove = Set.fromList
            [ a | (a, r) <- zip (Set.toList neighborhood) randoms
            , r < ratio ]
    in Schedule (Set.difference assignments toRemove)

-- | One iteration of the iterated greedy optimization:
-- 1. Get the current result (with unfilled positions)
-- 2. Find neighborhood of unfilled
-- 3. Destroy part of the neighborhood
-- 4. Rebuild with perturbed scoring
iteratedGreedyStep :: Schedule           -- ^ Seed (pinned assignments to preserve)
                   -> SchedulerContext
                   -> ScheduleResult     -- ^ Current best result
                   -> Double             -- ^ Randomness (destruction ratio + perturbation magnitude)
                   -> [Double]           -- ^ Random values for destruction decisions
                   -> [Double]           -- ^ Random values for score perturbations
                   -> GreedyStrategy     -- ^ Strategy for this iteration's rebuild
                   -> ScheduleResult
iteratedGreedyStep seed ctx currentResult randomness destroyRandoms perturbations strategy =
    let currentSched = srSchedule currentResult
        unfilled = srUnfilled currentResult
        -- Force intermediate Set operations so they don't chain across
        -- iterations (caller must deep-force the returned ScheduleResult).
        !hood = neighborhoodOf ctx unfilled currentSched
        -- Destroy neighborhood, but preserve seed (pinned) assignments
        seedSet = unSchedule seed
        !removableHood = Set.difference hood seedSet
        !destroyed = destroyNeighborhood randomness destroyRandoms removableHood currentSched
        -- Rebuild from the destroyed schedule using the given strategy
        cfg' = (schConfig ctx) { cfgGreedyStrategy = fromIntegral (fromEnum strategy) }
        ctx' = ctx { schConfig = cfg' }
    in buildScheduleFromPerturbed destroyed ctx'
           (randomness * 50.0) perturbations
           -- Scale perturbation magnitude: randomness 0.3 → ±15 score points

-- ---------------------------------------------------------------------
-- Local search moves (Phase 2: soft constraints)
-- ---------------------------------------------------------------------

-- | Try to swap two workers at a given slot.
-- Worker A moves from station stA to stB, worker B from stB to stA.
-- Returns Just the new schedule if both new assignments satisfy hard constraints.
trySwap :: SchedulerContext -> WorkerId -> StationId
        -> WorkerId -> StationId -> Slot -> Schedule -> Maybe Schedule
trySwap ctx wA stA wB stB slot sched =
    let -- Remove both old assignments
        oldA = Assignment wA stA slot
        oldB = Assignment wB stB slot
        sched1 = unassign oldA (unassign oldB sched)
        -- New assignments (swapped stations)
        newA = Assignment wA stB slot
        newB = Assignment wB stA slot
    in if canAssignSlot ctx True wA stB slot sched1
          && canAssignSlot ctx True wB stA slot sched1
       then Just (assign newA (assign newB sched1))
       else Nothing

-- | Propose candidate swaps by selecting pairs of assignments at the same slot.
-- Returns a list of (workerA, stationA, workerB, stationB, slot) tuples.
-- The @[Double]@ values drive random selection of slots and assignment pairs.
proposeSwaps :: Schedule -> [Double]
             -> [(WorkerId, StationId, WorkerId, StationId, Slot)]
proposeSwaps (Schedule assignments) randoms =
    let -- Group assignments by slot
        assignList = Set.toList assignments
        slotGroups = Map.fromListWith (++)
            [(assignSlot a, [a]) | a <- assignList]
        -- Only slots with 2+ assignments can produce swaps
        swappableSlots = Map.filter (\as -> length as >= 2) slotGroups
        slotList = Map.toList swappableSlots
    in if null slotList then []
       else concatMap (mkSwapsForSlot randoms) (zip [0..] slotList)
  where
    mkSwapsForSlot rs (idx, (slot, as)) =
        let -- Use random values to pick pairs
            n = length as
            pairs = [(as !! i, as !! j)
                    | i <- [0..n-2], j <- [i+1..n-1]]
        in [ ( assignWorker a1, assignStation a1
             , assignWorker a2, assignStation a2
             , slot )
           | (a1, a2) <- take (max 1 (length pairs `div` 2)) pairs
           , let rIdx = idx `mod` max 1 (length rs)
           , rIdx < length rs  -- always true but needed for safety
           ]

-- | One step of hill climbing for soft constraint optimization.
-- Proposes swaps and accepts the first that improves the total score.
-- Returns the (possibly improved) schedule and its score.
hillClimbStep :: SchedulerContext -> Schedule -> Double -> [Double]
              -> (Schedule, Double)
hillClimbStep ctx sched currentScore randoms =
    let swaps = proposeSwaps sched randoms
    in go swaps sched currentScore
  where
    -- BangPatterns on s and score prevent thunk buildup when iterating
    -- over many swap candidates without finding an improvement.
    go [] !s !score = (s, score)
    go ((wA, stA, wB, stB, slot):rest) !s !score =
        case trySwap ctx wA stA wB stB slot s of
            Nothing -> go rest s score
            Just s' ->
                let !score' = scoreSchedule ctx s'
                in if score' > score
                   then (s', score')
                   else go rest s score

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

-- Test fixtures
optw_alice, optw_bob, optw_carol :: WorkerId
optw_alice = WorkerId 1
optw_bob   = WorkerId 2
optw_carol = WorkerId 3

optsk_prep, optsk_cooking :: SkillId
optsk_prep    = SkillId 1
optsk_cooking = SkillId 2

optst_grill, optst_prep :: StationId
optst_grill = StationId 1
optst_prep  = StationId 2

optMkSlot :: Day -> Int -> Slot
optMkSlot d h = Slot d (TimeOfDay h 0 0) 3600

optMondaySlot :: Slot
optMondaySlot = optMkSlot (fromGregorian 2026 5 4) 9

optBasicSkillCtx :: SkillContext
optBasicSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (optw_alice, Set.singleton optsk_cooking)
        , (optw_bob,   Set.singleton optsk_cooking)
        , (optw_carol, Set.singleton optsk_prep)
        ]
    , scStationRequires = Map.fromList
        [ (optst_grill, Set.singleton optsk_cooking)
        , (optst_prep,  Set.singleton optsk_prep)
        ]
    , scSkillImplies = Map.fromList
        [ (optsk_cooking, Set.singleton optsk_prep)
        ]
    , scAllStations = Set.fromList [optst_grill, optst_prep]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

optWorkerCtx :: WorkerContext
optWorkerCtx = WorkerContext
    { wcMaxWeeklyHours = Map.fromList
        [ (optw_alice, 40 * 3600)
        , (optw_bob,   40 * 3600)
        , (optw_carol, 40 * 3600)
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
    }

optMkCtx :: [Slot] -> Set WorkerId -> SchedulerContext
optMkCtx slots workers = SchedulerContext
    optBasicSkillCtx optWorkerCtx emptyAbsenceContext
    slots workers Set.empty [] Set.empty defaultConfig

spec :: Spec
spec = do
    describe "scoreSchedule" $ do
        it "returns 0 for empty schedule" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice, optw_bob])
            scoreSchedule ctx emptySchedule `shouldBe` 0.0

        it "increases when assignments are added" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice, optw_bob])
                sched1 = assign (Assignment optw_alice optst_grill optMondaySlot) emptySchedule
                sched2 = assign (Assignment optw_carol optst_prep optMondaySlot) sched1
            scoreSchedule ctx sched2 `shouldSatisfy` (> scoreSchedule ctx sched1)

    describe "neighborhoodOf" $ do
        it "returns empty for no unfilled positions" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice])
                sched = assign (Assignment optw_alice optst_grill optMondaySlot) emptySchedule
            neighborhoodOf ctx [] sched `shouldBe` Set.empty

        it "includes assignments at unfilled slots" $ do
            let slot1 = optMkSlot (fromGregorian 2026 5 4) 9
                slot2 = optMkSlot (fromGregorian 2026 5 4) 10
                ctx = optMkCtx [slot1, slot2] (Set.fromList [optw_alice, optw_bob])
                sched = assign (Assignment optw_alice optst_grill slot1) emptySchedule
                unfilled = [Unfilled optst_prep slot1 TrulyUnfilled]
                hood = neighborhoodOf ctx unfilled sched
            Set.member (Assignment optw_alice optst_grill slot1) hood `shouldBe` True

    describe "destroyNeighborhood" $ do
        it "removes nothing with ratio 0" $ do
            let sched = assign (Assignment optw_alice optst_grill optMondaySlot) emptySchedule
                hood = Set.singleton (Assignment optw_alice optst_grill optMondaySlot)
            destroyNeighborhood 0.0 [0.5] hood sched `shouldBe` sched

        it "removes everything with ratio 1" $ do
            let sched = assign (Assignment optw_alice optst_grill optMondaySlot) emptySchedule
                hood = Set.singleton (Assignment optw_alice optst_grill optMondaySlot)
            destroyNeighborhood 1.0 [0.5] hood sched `shouldBe` emptySchedule

    describe "trySwap" $ do
        it "succeeds when both workers can take the new station" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice, optw_bob])
                sched = assign (Assignment optw_alice optst_grill optMondaySlot)
                      $ assign (Assignment optw_bob optst_prep optMondaySlot) emptySchedule
                -- alice (cooking → implies prep) can do prep
                -- bob (cooking) can do grill
            trySwap ctx optw_alice optst_grill optw_bob optst_prep optMondaySlot sched
                `shouldSatisfy` (/= Nothing)

        it "fails when a worker lacks the skill for the new station" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice, optw_carol])
                sched = assign (Assignment optw_alice optst_grill optMondaySlot)
                      $ assign (Assignment optw_carol optst_prep optMondaySlot) emptySchedule
                -- carol (prep only) cannot do grill
            trySwap ctx optw_alice optst_grill optw_carol optst_prep optMondaySlot sched
                `shouldBe` Nothing

    describe "hillClimbStep" $ do
        it "does not worsen the score" $ do
            let ctx = optMkCtx [optMondaySlot] (Set.fromList [optw_alice, optw_bob])
                sched = assign (Assignment optw_alice optst_grill optMondaySlot)
                      $ assign (Assignment optw_bob optst_prep optMondaySlot) emptySchedule
                score0 = scoreSchedule ctx sched
                (_, score1) = hillClimbStep ctx sched score0 [0.5, 0.3, 0.7]
            score1 `shouldSatisfy` (>= score0)
