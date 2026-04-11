module Domain.Diagnosis
    ( -- * Types
      Diagnosis(..)
    , UnfilledReason(..)
      -- * Diagnosis
    , diagnose
    , diagnoseUnfilled
      -- * Tests
    , spec
    ) where

import Data.List (sortBy, nub, group, sort)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Ord (Down(..))
import Data.Time (Day, TimeOfDay(..), fromGregorian)
import Test.Hspec

import Domain.Types
import Domain.Schedule (byWorkerSlot)
import Domain.Skill (SkillContext(..), effectiveSkills, qualified)
import Domain.Worker (WorkerContext(..), wouldBeOvertime, workerOptedInOvertime)
import Domain.SchedulerConfig (defaultConfig)
import Domain.Absence (emptyAbsenceContext, isWorkerAvailable)
import Domain.Scheduler hiding (spec)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | Why a particular station/slot could not be filled.
data UnfilledReason
    = NoQualifiedWorkers !StationId !Slot !(Set SkillId)
      -- ^ No worker in the pool has the required skills.
      -- Includes the missing skills.
    | AllQualifiedBusy !StationId !Slot ![WorkerId]
      -- ^ Qualified workers exist but are all assigned elsewhere
      -- at this slot. Lists the busy workers.
    | AllQualifiedOvertime !StationId !Slot ![WorkerId]
      -- ^ Qualified and unassigned workers exist but would exceed
      -- their hour limits. Lists the overtime-blocked workers.
    | AllQualifiedAbsent !StationId !Slot ![WorkerId]
      -- ^ Qualified workers exist but are on approved absence.
    deriving (Eq, Ord, Show)

-- | A suggested action to resolve unfilled positions.
data Diagnosis
    = SuggestHire !(Set SkillId) !Int
      -- ^ Hire a worker with these skills; would resolve N unfilled.
    | SuggestTraining !WorkerId !SkillId !Int
      -- ^ Train this worker in this skill; would let them cover
      -- N additional unfilled positions.
    | SuggestOvertime ![WorkerId] !Int
      -- ^ These workers could fill N positions if given overtime.
    | SuggestClose !StationId ![Slot] !Int
      -- ^ Closing this station at these slots would free N workers
      -- for other stations.
    | SuggestAddWorker !(Set SkillId)
      -- ^ Bring in a temporary worker with these skills.
    deriving (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Diagnosis
-- ---------------------------------------------------------------------

-- | Analyze unfilled positions and suggest actions.
-- Returns diagnoses sorted by impact (most positions resolved first).
diagnose :: ScheduleResult -> SchedulerContext -> [Diagnosis]
diagnose result ctx =
    let unfilled = srUnfilled result
        sched = srSchedule result
        reasons = map (diagnoseOne ctx sched) unfilled
        suggestions = concatMap (suggestFromReason ctx sched) reasons
            ++ suggestHires ctx unfilled
            ++ suggestTrainings ctx sched unfilled
    in rankDiagnoses (nub suggestions)

-- | Diagnose why a single station/slot is unfilled.
diagnoseUnfilled :: SchedulerContext -> Schedule -> Unfilled -> UnfilledReason
diagnoseUnfilled = diagnoseOne

diagnoseOne :: SchedulerContext -> Schedule -> Unfilled -> UnfilledReason
diagnoseOne ctx sched (Unfilled st t _kind) =
    let allW = Set.toList (schWorkers ctx)
        sctx = schSkillCtx ctx
        wctx = schWorkerCtx ctx
        actx = schAbsenceCtx ctx
        qualifiedW = filter (\w -> qualified sctx w st) allW
    in case qualifiedW of
        [] ->
            let required = Map.findWithDefault Set.empty st (scStationRequires sctx)
            in NoQualifiedWorkers st t required
        qs ->
            let absent  = filter (\w -> not (isWorkerAvailable w (slotDate t) actx)) qs
                present = filter (\w -> isWorkerAvailable w (slotDate t) actx) qs
                busy    = filter (\w -> not (Set.null (byWorkerSlot w t sched))) present
                free    = filter (\w -> Set.null (byWorkerSlot w t sched)) present
                overtimeBlocked = filter (\w ->
                    let a = Assignment w st t
                    in wouldBeOvertime wctx sched a
                       && not (workerOptedInOvertime wctx w)) free
            in if not (null absent) && null present
               then AllQualifiedAbsent st t absent
               else if not (null busy) && null free
               then AllQualifiedBusy st t busy
               else if not (null overtimeBlocked)
               then AllQualifiedOvertime st t overtimeBlocked
               else if null free
               then AllQualifiedBusy st t busy
               else -- Free qualified workers exist but blocked by daily
                    -- rules (break, rest period). Report as busy.
                    AllQualifiedBusy st t free

-- | Suggest actions based on a single unfilled reason.
suggestFromReason :: SchedulerContext -> Schedule -> UnfilledReason -> [Diagnosis]
suggestFromReason _ _ (NoQualifiedWorkers _ _ skills) =
    [SuggestAddWorker skills]
suggestFromReason _ _ (AllQualifiedBusy st slots ws) =
    [SuggestClose st [slots] (length ws)]
suggestFromReason _ _ (AllQualifiedOvertime _ _ ws)
    | null ws   = []
    | otherwise = [SuggestOvertime ws (length ws)]
suggestFromReason _ _ (AllQualifiedAbsent _ _ _) =
    []  -- Can't do much about absences; suggest hire instead

-- | Analyze all unfilled positions to suggest skill-based hires.
-- Groups by required skill set and counts how many positions each
-- hire would resolve.
suggestHires :: SchedulerContext -> [Unfilled] -> [Diagnosis]
suggestHires ctx unfilled =
    let sctx = schSkillCtx ctx
        allW = Set.toList (schWorkers ctx)
        -- Only suggest hires for stations where no current worker qualifies
        needsHire = filter (\(Unfilled st _ _) ->
            not (any (\w -> qualified sctx w st) allW)) unfilled
        skillSets = map (\(Unfilled st _ _) ->
            Map.findWithDefault Set.empty st (scStationRequires sctx)) needsHire
        grouped = [(s, length g) | g@(s:_) <- group (sort skillSets)]
    in [SuggestHire skills count | (skills, count) <- grouped, not (Set.null skills)]

-- | Suggest training opportunities: find workers who are close to
-- qualifying for understaffed stations (missing exactly one skill).
-- Only counts positions where the worker has available hours.
suggestTrainings :: SchedulerContext -> Schedule -> [Unfilled] -> [Diagnosis]
suggestTrainings ctx sched unfilled =
    let sctx = schSkillCtx ctx
        wctx = schWorkerCtx ctx
        allW = Set.toList (schWorkers ctx)
        suggestions =
            [ (w, missingSk, st)
            | Unfilled st slot _ <- unfilled
            , w <- allW
            , not (qualified sctx w st)
            , let required = Map.findWithDefault Set.empty st (scStationRequires sctx)
                  effective = effectiveSkills sctx
                      (Map.findWithDefault Set.empty w (scWorkerSkills sctx))
                  missing = Set.difference required effective
            , Set.size missing == 1
            , let missingSk = Set.findMin missing
            -- Worker must have available hours for this slot
            , let hypothetical = Assignment w st slot
            , not (wouldBeOvertime wctx sched hypothetical)
            ]
        -- Group by (worker, skill) and count how many positions each training helps
        grouped = [(k, length g) | g@((k, _):_) <- group (sort pairs)]
        pairs = map (\(w, sk, _) -> ((w, sk), ())) suggestions
    in [ SuggestTraining w sk count
       | ((w, sk), count) <- grouped
       ]

-- | Sort diagnoses by impact (most positions resolved first).
rankDiagnoses :: [Diagnosis] -> [Diagnosis]
rankDiagnoses = sortBy (\a b -> compare (Down (diagImpact a)) (Down (diagImpact b)))

diagImpact :: Diagnosis -> Int
diagImpact (SuggestHire _ n)       = n
diagImpact (SuggestTraining _ _ n) = n
diagImpact (SuggestOvertime _ n)   = n
diagImpact (SuggestClose _ _ n)    = n
diagImpact (SuggestAddWorker _)    = 1

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

dw_alice, dw_bob, dw_carol :: WorkerId
dw_alice = WorkerId 1
dw_bob   = WorkerId 2
dw_carol = WorkerId 3

dsk_prep, dsk_cooking, dsk_cleaning :: SkillId
dsk_prep     = SkillId 1
dsk_cooking  = SkillId 2
dsk_cleaning = SkillId 4

dst_grill, dst_prep_table, dst_dish :: StationId
dst_grill      = StationId 1
dst_prep_table = StationId 2
dst_dish       = StationId 3

dMkSlot :: Day -> Int -> Slot
dMkSlot d h = Slot d (TimeOfDay h 0 0) 3600

dMondaySlot :: Slot
dMondaySlot = dMkSlot (fromGregorian 2026 5 4) 9

dTuesdaySlot :: Slot
dTuesdaySlot = dMkSlot (fromGregorian 2026 5 5) 9

-- | Skill context with a dish station that requires cleaning (nobody has it).
dSkillCtx :: SkillContext
dSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (dw_alice, Set.singleton dsk_cooking)
        , (dw_bob,   Set.singleton dsk_cooking)
        , (dw_carol, Set.singleton dsk_prep)
        ]
    , scStationRequires = Map.fromList
        [ (dst_grill,      Set.singleton dsk_cooking)
        , (dst_prep_table, Set.singleton dsk_prep)
        , (dst_dish,       Set.singleton dsk_cleaning)
        ]
    , scSkillImplies = Map.fromList
        [ (dsk_cooking, Set.singleton dsk_prep)
        ]
    , scAllStations = Set.fromList [dst_grill, dst_prep_table, dst_dish]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

dWorkerCtx :: WorkerContext
dWorkerCtx = WorkerContext
    { wcMaxWeeklyHours = Map.fromList
        [ (dw_alice, 40 * 3600)
        , (dw_bob,   40 * 3600)
        , (dw_carol, 40 * 3600)
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

-- | Worker context where bob has very tight hours.
dTightWorkerCtx :: WorkerContext
dTightWorkerCtx = dWorkerCtx
    { wcMaxWeeklyHours = Map.fromList
        [ (dw_alice, 40 * 3600)
        , (dw_bob,   1 * 3600)
        , (dw_carol, 40 * 3600)
        ]
    }

dBaseCtx :: SchedulerContext
dBaseCtx = SchedulerContext dSkillCtx dWorkerCtx emptyAbsenceContext
    [dMondaySlot] (Set.fromList [dw_alice, dw_bob, dw_carol]) Set.empty [] Set.empty defaultConfig

spec :: Spec
spec = do
    describe "diagnoseUnfilled" $ do
        it "identifies NoQualifiedWorkers when nobody has the skill" $ do
            let result = buildSchedule dBaseCtx
                dishUnfilled = filter (\u -> unfilledStation u == dst_dish) (srUnfilled result)
            dishUnfilled `shouldSatisfy` (not . null)
            case dishUnfilled of
                (u:_) -> case diagnoseUnfilled dBaseCtx (srSchedule result) u of
                    NoQualifiedWorkers _ _ skills ->
                        skills `shouldBe` Set.singleton dsk_cleaning
                    other -> expectationFailure ("expected NoQualifiedWorkers, got " ++ show other)
                [] -> expectationFailure "expected unfilled dish station"

        it "identifies AllQualifiedBusy when workers are at other stations" $ do
            -- alice can cook (for grill), carol can prep (for prep_table).
            -- dish requires cleaning — nobody has it, but alice gets
            -- assigned to grill instead. We need a scenario where qualified
            -- workers exist but are all busy. Use grill + prep_table + dish
            -- with only alice and carol: grill gets alice, prep gets carol,
            -- dish is unfilled but nobody is qualified → that's NoQualified.
            -- For AllQualifiedBusy: add a second cooking station. Only alice
            -- can cook; she's at grill, so the second cooking station is unfilled.
            let dst_grill2 = StationId 4
                busyCtx = dBaseCtx
                    { schSkillCtx = dSkillCtx
                        { scStationRequires = Map.fromList
                            [ (dst_grill,  Set.singleton dsk_cooking)
                            , (dst_grill2, Set.singleton dsk_cooking)
                            , (dst_prep_table, Set.singleton dsk_prep)
                            ]
                        , scAllStations = Set.fromList [dst_grill, dst_grill2, dst_prep_table]
                        }
                    , schWorkers = Set.fromList [dw_alice, dw_carol]
                    }
                result = buildSchedule busyCtx
                grill2Unfilled = filter (\u -> unfilledStation u == dst_grill2) (srUnfilled result)
            grill2Unfilled `shouldSatisfy` (not . null)
            case grill2Unfilled of
                (u:_) -> case diagnoseUnfilled busyCtx (srSchedule result) u of
                    AllQualifiedBusy _ _ _ -> return ()
                    other -> expectationFailure ("expected AllQualifiedBusy, got " ++ show other)
                [] -> expectationFailure "expected unfilled grill2 station"

        it "identifies AllQualifiedOvertime when workers are at their limit" $ do
            let twoSlotCtx = dBaseCtx
                    { schWorkerCtx = dTightWorkerCtx
                    , schSlots = [dMondaySlot, dTuesdaySlot]
                    , schSkillCtx = dSkillCtx
                        { scAllStations = Set.fromList [dst_grill, dst_prep_table] }
                    , schWorkers = Set.fromList [dw_bob, dw_carol]
                    }
                result = buildSchedule twoSlotCtx
                grillUnfilled = filter (\u -> unfilledStation u == dst_grill) (srUnfilled result)
            grillUnfilled `shouldSatisfy` (not . null)
            case grillUnfilled of
                (u:_) -> case diagnoseUnfilled twoSlotCtx (srSchedule result) u of
                    AllQualifiedOvertime _ _ ws ->
                        ws `shouldSatisfy` (elem dw_bob)
                    other -> expectationFailure ("expected AllQualifiedOvertime, got " ++ show other)
                [] -> expectationFailure "expected unfilled grill station"

    describe "diagnose" $ do
        it "suggests hiring when no worker has the required skill" $ do
            let result = buildSchedule dBaseCtx
                diags = diagnose result dBaseCtx
                hires = [sk | SuggestHire sk _ <- diags]
            hires `shouldSatisfy` any (Set.member dsk_cleaning)

        it "suggests adding a temp worker for skill gaps" $ do
            let result = buildSchedule dBaseCtx
                diags = diagnose result dBaseCtx
                adds = [sk | SuggestAddWorker sk <- diags]
            adds `shouldSatisfy` any (Set.member dsk_cleaning)

        it "suggests overtime when workers are hour-blocked" $ do
            let twoSlotCtx = dBaseCtx
                    { schWorkerCtx = dTightWorkerCtx
                    , schSlots = [dMondaySlot, dTuesdaySlot]
                    , schSkillCtx = dSkillCtx
                        { scAllStations = Set.fromList [dst_grill, dst_prep_table] }
                    , schWorkers = Set.fromList [dw_bob, dw_carol]
                    }
                result = buildSchedule twoSlotCtx
                diags = diagnose result twoSlotCtx
                otSuggestions = [ws | SuggestOvertime ws _ <- diags]
            otSuggestions `shouldSatisfy` any (elem dw_bob)

        it "suggests training when a worker is one skill away" $ do
            -- carol has prep but not cooking; grill requires cooking
            -- cooking implies prep, so carol is one skill away from grill
            -- Two grill stations force an unfilled position that carol
            -- could cover if she learned cooking.
            let dst_grill2 = StationId 5
                limitedCtx = dBaseCtx
                    { schSkillCtx = dSkillCtx
                        { scAllStations = Set.fromList [dst_grill, dst_grill2, dst_prep_table]
                        , scStationRequires = Map.fromList
                            [ (dst_grill,      Set.singleton dsk_cooking)
                            , (dst_grill2,     Set.singleton dsk_cooking)
                            , (dst_prep_table, Set.singleton dsk_prep)
                            ]
                        }
                    , schWorkers = Set.fromList [dw_alice, dw_carol]
                    }
                result = buildSchedule limitedCtx
                diags = diagnose result limitedCtx
                trainSuggestions = [(w, sk) | SuggestTraining w sk _ <- diags]
            trainSuggestions `shouldSatisfy` elem (dw_carol, dsk_cooking)

        it "returns empty for a fully-filled schedule" $ do
            let fullCtx = dBaseCtx
                    { schSkillCtx = dSkillCtx
                        { scAllStations = Set.fromList [dst_grill, dst_prep_table] }
                    }
                result = buildSchedule fullCtx
            srUnfilled result `shouldBe` []
            diagnose result fullCtx `shouldBe` []

        it "ranks by impact (more positions resolved first)" $ do
            let multiSlotCtx = dBaseCtx
                    { schSlots = [dMondaySlot, dTuesdaySlot]
                    }
                result = buildSchedule multiSlotCtx
                diags = diagnose result multiSlotCtx
                impacts = map diagImpact diags
            -- Should be in non-increasing order
            impacts `shouldBe` sortBy (flip compare) impacts
