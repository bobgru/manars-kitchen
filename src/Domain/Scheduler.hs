module Domain.Scheduler
    ( -- * Types
      SchedulerContext(..)
    , ScheduleResult(..)
    , Unfilled(..)
    , UnfilledKind(..)
    , GreedyStrategy(..)
    , strategyFromDouble
    , allStrategies
      -- * Scheduling
    , buildSchedule
    , buildScheduleFrom
    , buildScheduleFromPerturbed
      -- * Scoring (for optimizer)
    , scoreShiftWorker
    , scoreSlotWorker
    , canAssignSlot
      -- * Constraint checks (for validation)
    , blockedByAlternateWeekend
      -- * Tests
    , spec
    ) where

import Data.List (sortBy, nubBy)
import Data.Function (on)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set

import Data.Time (Day, DayOfWeek(..), TimeOfDay(..), addDays, fromGregorian, dayOfWeek)
import Test.Hspec

import Domain.Types
import Domain.Schedule (assign, byWorker, byWorkerSlot, bySlot, scheduleSize)
import Domain.Skill (SkillContext(..), qualified, couldQualifyViaCrossTraining,
                     stationStaffCount, isMultiStationSlot)
import Domain.Worker hiding (spec)
import Domain.SchedulerConfig (SchedulerConfig(..), defaultConfig)
import Domain.Shift (ShiftDef(..), ShiftBlock(..), defaultShifts, groupSlotsByShift)
import Domain.Absence (AbsenceType(..), AbsenceContext(..), emptyAbsenceContext,
                       isWorkerAvailable, requestAbsence, approveAbsence)

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------

-- | All context needed for scheduling.
data SchedulerContext = SchedulerContext
    { schSkillCtx    :: !SkillContext
    , schWorkerCtx   :: !WorkerContext
    , schAbsenceCtx  :: !AbsenceContext
      -- ^ Absence context; workers with approved absences on a slot's
      -- day are excluded from scheduling for that slot.
    , schSlots       :: ![Slot]
      -- ^ All slots to fill, typically a month's worth.
    , schWorkers     :: !(Set WorkerId)
      -- ^ All available workers.
    , schClosedSlots :: !(Set (StationId, Slot))
      -- ^ Station/slot pairs that are closed (not to be staffed).
      -- Used by the hint system to temporarily close stations.
    , schShifts :: ![ShiftDef]
      -- ^ Shift definitions. If empty, 'defaultShifts' is used.
    , schPrevWeekendWorkers :: !(Set WorkerId)
      -- ^ Workers who worked the previous weekend. Used to enforce
      -- the alternating-weekends-off rule: these workers are not
      -- assigned to weekend slots unless they are weekend-only.
    , schConfig :: !SchedulerConfig
      -- ^ Scoring weights and rule thresholds.
    } deriving (Show)

-- | Whether a position is completely unstaffed or just short of the
-- desired overlap level.
data UnfilledKind
    = TrulyUnfilled
      -- ^ Zero workers assigned at this station/slot.
    | Understaffed
      -- ^ At least one worker is present (from another shift block),
      -- but an overlapping block could not place an additional worker.
    deriving (Eq, Ord, Show)

-- | A station/slot pair that could not be filled.
data Unfilled = Unfilled
    { unfilledStation :: !StationId
    , unfilledSlot    :: !Slot
    , unfilledKind    :: !UnfilledKind
    } deriving (Eq, Ord, Show)

-- | Result of the scheduling process.
data ScheduleResult = ScheduleResult
    { srSchedule :: !Schedule
      -- ^ The best schedule we could build.
    , srUnfilled :: ![Unfilled]
      -- ^ Positions we could not fill.
    , srOvertime :: !(Map WorkerId DiffTime)
      -- ^ Overtime hours incurred per worker (only workers with overtime > 0).
    } deriving (Show)

-- | Greedy fill strategies that control Phase 1 traversal order.
data GreedyStrategy
    = BottleneckFirst
      -- ^ Sort stations by fewest qualified candidates (MRV heuristic).
    | Chronological
      -- ^ Blocks in chronological order, stations in set order (original).
    | ReverseChronological
      -- ^ Blocks in reverse chronological order.
    | RandomShuffle
      -- ^ Shuffle block and station order using perturbation stream.
    | WorkerFirst
      -- ^ Iterate workers (most constrained first), assign to best station.
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

-- | Decode a Double config value to a strategy.
strategyFromDouble :: Double -> GreedyStrategy
strategyFromDouble d
    | d < 0.5   = BottleneckFirst
    | d < 1.5   = Chronological
    | d < 2.5   = ReverseChronological
    | d < 3.5   = RandomShuffle
    | otherwise  = WorkerFirst

-- | All available strategies.
allStrategies :: [GreedyStrategy]
allStrategies = [minBound .. maxBound]

-- ---------------------------------------------------------------------
-- Scheduling algorithm (greedy)
-- ---------------------------------------------------------------------

-- | Build a schedule by greedily assigning workers to stations.
--
-- Algorithm (shift-based):
--   1. Group slots into shift blocks (morning, afternoon, evening).
--   2. For each shift block, assign workers to stations for the entire
--      shift, ensuring contiguous assignments with no gaps.
--   3. Phase 1: fill to minimums, no overtime.
--   4. Phase 2: retry unfilled shift blocks with overtime.
--   5. Phase 3-4: fill to maximum capacity.
--   6. Phase 5: gap-fill remaining individual slots (for floaters/breaks).
buildSchedule :: SchedulerContext -> ScheduleResult
buildSchedule = buildScheduleFrom emptySchedule

-- | Build a schedule starting from a seed (e.g., pinned assignments).
buildScheduleFrom :: Schedule -> SchedulerContext -> ScheduleResult
buildScheduleFrom seed ctx = buildScheduleFromPerturbed seed ctx 0.0 (repeat 0.0)

-- | Build a schedule with randomized score perturbations.
-- The 'Double' parameter is the perturbation magnitude (0.0 = deterministic).
-- The '[Double]' is a lazy stream of random values in [0,1) consumed during
-- worker selection to break ties and explore alternative assignments.
buildScheduleFromPerturbed :: Schedule -> SchedulerContext -> Double -> [Double]
                           -> ScheduleResult
buildScheduleFromPerturbed seed ctx magnitude perturbations =
    let sortedSlots = sortBy compare (schSlots ctx)
        shifts = case schShifts ctx of
            [] -> defaultShifts
            ss -> ss
        blocks = groupSlotsByShift shifts sortedSlots
        strategy = strategyFromDouble (cfgGreedyStrategy (schConfig ctx))
        -- Phase 1: strategy-dependent greedy fill, no overtime
        (sched1, unfilled1, ps1) = runPhase1 strategy ctx False magnitude perturbations blocks seed
        -- Phase 2: retry unfilled with overtime (slot-level)
        (sched2, unfilled2, ps2) = retryUnfilledSlotsP ctx magnitude ps1 sched1 unfilled1
        -- Phase 3: gap-fill remaining individual unfilled slots
        (sched3, unfilled3, _ps3) = gapFillP ctx magnitude ps2 sched2 unfilled2
        overtime = computeOvertime ctx sched3
        -- Deduplicate: same (station, slot) may appear from overlapping
        -- blocks. Keep the worst severity (TrulyUnfilled < Understaffed
        -- in Ord, so sorting puts TrulyUnfilled first per key).
        sorted = sortBy (compare `on` (\u -> (unfilledStation u, unfilledSlot u, unfilledKind u))) unfilled3
        deduped = nubBy ((==) `on` (\u -> (unfilledStation u, unfilledSlot u))) sorted
    in ScheduleResult sched3 deduped overtime

-- ---------------------------------------------------------------------
-- Phase 1: Shift-block-based filling (1 worker per station per block)
-- ---------------------------------------------------------------------

-- | Fill all shift blocks with perturbation support.
fillBlocksP :: SchedulerContext -> Bool -> Double -> [Double] -> [ShiftBlock]
            -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlocksP _ _ _ ps [] sched = (sched, [], ps)
fillBlocksP ctx allowOT mag ps (b:bs) sched =
    let (sched', unfilled, ps') = fillBlockP ctx allowOT mag ps b sched
        (sched'', more, ps'') = fillBlocksP ctx allowOT mag ps' bs sched'
    in (sched'', unfilled ++ more, ps'')

-- | Fill a single shift block with perturbation support.
fillBlockP :: SchedulerContext -> Bool -> Double -> [Double] -> ShiftBlock
           -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlockP ctx allowOT mag ps block sched =
    let sctx = schSkillCtx ctx
        stations = Set.toList (scAllStations sctx)
        -- A station needs a worker for this block if any active slot
        -- has no assignment yet.
        needsWork st = any (\s -> not (isClosed ctx s st)
                                  && stationStaffCount st s sched == 0)
                           (sbSlots block)
    in foldl (\(sc, uf, ps') st -> fillStationBlockP ctx allowOT mag ps' block (sc, uf) st)
             (sched, [], ps) (filter needsWork stations)

-- | Fill one station for a shift block with perturbation support.
fillStationBlockP :: SchedulerContext -> Bool -> Double -> [Double] -> ShiftBlock
                  -> (Schedule, [Unfilled]) -> StationId
                  -> (Schedule, [Unfilled], [Double])
fillStationBlockP ctx allowOT mag ps block (sched, unfilled) st =
    let activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
    in case activeSlots of
        [] -> (sched, unfilled, ps)
        _  -> let nCandidates = Set.size (schWorkers ctx)
                  (used, ps') = splitAt nCandidates ps
              in case pickShiftWorkerP ctx allowOT mag used block st sched of
            Nothing ->
                let newUnfilled =
                        [ Unfilled st s kind
                        | s <- activeSlots
                        , let count = stationStaffCount st s sched
                        , let kind = if count == 0
                                     then TrulyUnfilled
                                     else Understaffed
                        ]
                in (sched, unfilled ++ newUnfilled, ps')
            Just w ->
                -- assignWorkerToShift may skip individual slots (break rules,
                -- daily limits, etc.).  Detect any gaps so Phase 2/3 can fill them.
                let sched' = assignWorkerToShift ctx allowOT w st activeSlots sched
                    gaps = [ Unfilled st s TrulyUnfilled
                           | s <- activeSlots
                           , stationStaffCount st s sched' == 0
                           ]
                in (sched', unfilled ++ gaps, ps')

-- ---------------------------------------------------------------------
-- Phase 1 strategy dispatcher
-- ---------------------------------------------------------------------

-- | Dispatch Phase 1 to the configured greedy strategy.
runPhase1 :: GreedyStrategy -> SchedulerContext -> Bool -> Double -> [Double]
          -> [ShiftBlock] -> Schedule -> (Schedule, [Unfilled], [Double])
runPhase1 Chronological        ctx ot mag ps blocks seed = fillBlocksP ctx ot mag ps blocks seed
runPhase1 ReverseChronological ctx ot mag ps blocks seed = fillBlocksP ctx ot mag ps (reverse blocks) seed
runPhase1 BottleneckFirst      ctx ot mag ps blocks seed = fillBlocksBottleneck ctx ot mag ps blocks seed
runPhase1 RandomShuffle        ctx ot mag ps blocks seed = fillBlocksShuffle ctx ot mag ps blocks seed
runPhase1 WorkerFirst          ctx ot mag ps blocks seed = fillBlocksWorkerFirst ctx ot mag ps blocks seed

-- ---------------------------------------------------------------------
-- BottleneckFirst: sort stations by fewest candidates (MRV heuristic)
-- ---------------------------------------------------------------------

fillBlocksBottleneck :: SchedulerContext -> Bool -> Double -> [Double] -> [ShiftBlock]
                     -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlocksBottleneck _ _ _ ps [] sched = (sched, [], ps)
fillBlocksBottleneck ctx allowOT mag ps (b:bs) sched =
    let (sched', unfilled, ps') = fillBlockBottleneck ctx allowOT mag ps b sched
        (sched'', more, ps'') = fillBlocksBottleneck ctx allowOT mag ps' bs sched'
    in (sched'', unfilled ++ more, ps'')

-- | Fill a single block, sorting stations by candidate count (ascending).
-- Most constrained stations get first pick of workers.
fillBlockBottleneck :: SchedulerContext -> Bool -> Double -> [Double] -> ShiftBlock
                    -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlockBottleneck ctx allowOT mag ps block sched =
    let sctx = schSkillCtx ctx
        stations = Set.toList (scAllStations sctx)
        needsWork st = any (\s -> not (isClosed ctx s st)
                                  && stationStaffCount st s sched == 0)
                           (sbSlots block)
        needed = filter needsWork stations
        -- MRV: sort by fewest qualified candidates
        candidateCount st =
            let activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
            in length (filter (isShiftCandidate ctx allowOT st activeSlots sched)
                              (Set.toList (schWorkers ctx)))
        sorted = sortBy (compare `on` candidateCount) needed
    in foldl (\(sc, uf, ps') st -> fillStationBlockP ctx allowOT mag ps' block (sc, uf) st)
             (sched, [], ps) sorted

-- ---------------------------------------------------------------------
-- RandomShuffle: shuffle block and station order via perturbation stream
-- ---------------------------------------------------------------------

fillBlocksShuffle :: SchedulerContext -> Bool -> Double -> [Double] -> [ShiftBlock]
                  -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlocksShuffle _ _ _ ps [] sched = (sched, [], ps)
fillBlocksShuffle ctx allowOT mag ps blocks sched =
    let (shuffled, ps') = fisherYatesShuffle ps blocks
    in go ctx allowOT mag ps' shuffled sched
  where
    go _ _ _ ps' [] sc = (sc, [], ps')
    go cx ot mg ps' (b:bs) sc =
        let (sc', uf, ps'') = fillBlockShuffled cx ot mg ps' b sc
            (sc'', more, ps''') = go cx ot mg ps'' bs sc'
        in (sc'', uf ++ more, ps''')

-- | Fill a single block with shuffled station order.
fillBlockShuffled :: SchedulerContext -> Bool -> Double -> [Double] -> ShiftBlock
                  -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlockShuffled ctx allowOT mag ps block sched =
    let sctx = schSkillCtx ctx
        stations = Set.toList (scAllStations sctx)
        needsWork st = any (\s -> not (isClosed ctx s st)
                                  && stationStaffCount st s sched == 0)
                           (sbSlots block)
        needed = filter needsWork stations
        (shuffled, ps') = fisherYatesShuffle ps needed
    in foldl (\(sc, uf, ps'') st -> fillStationBlockP ctx allowOT mag ps'' block (sc, uf) st)
             (sched, [], ps') shuffled

-- | Pure Fisher-Yates shuffle driven by a stream of random Doubles in [0,1).
-- Consumes one Double per element. Returns the shuffled list and remaining stream.
fisherYatesShuffle :: [Double] -> [a] -> ([a], [Double])
fisherYatesShuffle ps [] = ([], ps)
fisherYatesShuffle ps [x] = ([x], ps)
fisherYatesShuffle ps xs =
    let arr0 = Map.fromList (zip [0..] xs)
        n = length xs
    in go (n - 1) ps arr0
  where
    go 0 ps' arr = (map snd (Map.toAscList arr), ps')
    go i (r:rs) arr =
        let j = floor (r * fromIntegral (i + 1)) `mod` (i + 1)
            ai = arr Map.! i
            aj = arr Map.! j
            arr' = Map.insert i aj (Map.insert j ai arr)
        in go (i - 1) rs arr'
    go _ [] arr = (map snd (Map.toAscList arr), [])  -- shouldn't happen with infinite stream

-- ---------------------------------------------------------------------
-- WorkerFirst: iterate workers (most constrained first), assign to best
-- ---------------------------------------------------------------------

fillBlocksWorkerFirst :: SchedulerContext -> Bool -> Double -> [Double] -> [ShiftBlock]
                      -> Schedule -> (Schedule, [Unfilled], [Double])
fillBlocksWorkerFirst ctx allowOT mag ps blocks seed =
    let sctx = schSkillCtx ctx
        workers = Set.toList (schWorkers ctx)
        -- MRV: sort workers by fewest qualified stations (most constrained first)
        qualifiedCount w = length
            [ st | st <- Set.toList (scAllStations sctx)
            , qualified sctx w st
              || couldQualifyViaCrossTraining sctx (schWorkerCtx ctx) w st
            ]
        sortedWorkers = sortBy (compare `on` qualifiedCount) workers
        -- Assign each worker to as many blocks as they can work
        (sched', ps') = foldl (\(sc, ps'') w -> assignWorkerToAllBlocks ctx allowOT mag ps'' blocks w sc)
                              (seed, ps) sortedWorkers
        -- Collect unfilled positions for Phase 2/3
        unfilled = [ Unfilled st s TrulyUnfilled
                   | b <- blocks
                   , st <- Set.toList (scAllStations sctx)
                   , s <- sbSlots b
                   , not (isClosed ctx s st)
                   , stationStaffCount st s sched' == 0
                   ]
    in (sched', unfilled, ps')

-- | Greedily assign a worker to (block, station) pairs until they can't
-- take more (hours exhausted, no valid assignments remain).
assignWorkerToAllBlocks :: SchedulerContext -> Bool -> Double -> [Double]
                        -> [ShiftBlock] -> WorkerId -> Schedule
                        -> (Schedule, [Double])
assignWorkerToAllBlocks ctx allowOT mag ps blocks w sched =
    case findBestAssignment ctx allowOT mag ps blocks w sched of
        Nothing -> (sched, ps)
        Just (block, st, ps') ->
            let activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
                sched' = assignWorkerToShift ctx allowOT w st activeSlots sched
            in assignWorkerToAllBlocks ctx allowOT mag ps' blocks w sched'

-- | Find the best (block, station) pair for a worker.
-- Returns Nothing if no valid assignment exists.
findBestAssignment :: SchedulerContext -> Bool -> Double -> [Double]
                   -> [ShiftBlock] -> WorkerId -> Schedule
                   -> Maybe (ShiftBlock, StationId, [Double])
findBestAssignment ctx allowOT mag ps blocks w sched =
    let sctx = schSkillCtx ctx
        candidates =
            [ (block, st, scoreShiftWorker ctx block st sched w)
            | block <- blocks
            , st <- Set.toList (scAllStations sctx)
            , let activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
            , not (null activeSlots)
            , any (\s -> stationStaffCount st s sched == 0) activeSlots
            , isShiftCandidate ctx allowOT st activeSlots sched w
            ]
        nCandidates = length candidates
        (used, ps') = splitAt nCandidates ps
        scored = zipWith (\(b, st, sc) p -> (b, st, sc + mag * p)) candidates used
        ranked = sortBy (flip (compare `on` (\(_, _, s) -> s))) scored
    in case ranked of
        [] -> Nothing
        ((bestBlock, bestSt, _):_) -> Just (bestBlock, bestSt, ps')

-- ---------------------------------------------------------------------

-- | Assign a worker to all workable slots in a shift at a station.
-- Respects break, daily limit, and rest period rules.
assignWorkerToShift :: SchedulerContext -> Bool -> WorkerId -> StationId
                    -> [Slot] -> Schedule -> Schedule
assignWorkerToShift ctx allowOT w st slots sched =
    foldl (\sc slot ->
        if canAssignSlot ctx allowOT w st slot sc
        then assign (Assignment w st slot) sc
        else sc
    ) sched slots

-- | Can a worker be assigned to a specific slot at a station?
canAssignSlot :: SchedulerContext -> Bool -> WorkerId -> StationId
              -> Slot -> Schedule -> Bool
canAssignSlot ctx allowOT w st slot sched =
    skillOk
    && isWorkerAvailable w (slotDate slot) (schAbsenceCtx ctx)
    && slotAvailable
    && not (needsBreak cfg w slot sched)
    && not (violatesRestPeriod cfg w slot sched)
    && not (blockedByAlternateWeekend ctx w slot)
    && not avoidBlocked
    && weeklyOk && dailyOk
  where
    cfg = schConfig ctx
    a = Assignment w st slot
    wctx = schWorkerCtx ctx
    sctx = schSkillCtx ctx
    existing = byWorkerSlot w slot sched
    -- Hard constraint: block if any worker at this slot is in our avoid set
    avoidBlocked =
        let othersAtSlot = Set.map assignWorker (bySlot slot sched)
        in workerAvoidsAt wctx w othersAtSlot
    seniorityLvl = workerSeniority wctx w
    -- Skill check: qualified directly, OR qualifies via cross-training
    -- when a higher-seniority worker is present at the slot.
    skillOk = qualified sctx w st || crossTrainingOk
    crossTrainingOk =
        couldQualifyViaCrossTraining sctx wctx w st
        && hasMentorAtSlot ctx w slot sched
    -- Multi-station: allow additional assignments up to seniority level
    -- if the station permits it during multi-station hours
    slotAvailable =
        if Set.null existing
        then True  -- no existing assignment, always OK
        else isMultiStationSlot sctx st slot
             && Set.size existing < seniorityLvl + 1
             && not (any (\ea -> assignStation ea == st) (Set.toList existing))
    weeklyOk = if allowOT
               then not (wouldBeOvertime wctx sched a)
                    || workerOptedInOvertime wctx w
               else not (wouldBeOvertime wctx sched a)
    dailyOk = if allowOT
              then not (wouldExceedDailyTotal cfg a sched)
              else not (wouldExceedDailyRegular cfg a sched)

-- | Is there a higher-seniority worker already assigned at this slot?
hasMentorAtSlot :: SchedulerContext -> WorkerId -> Slot -> Schedule -> Bool
hasMentorAtSlot ctx w slot sched =
    let wctx = schWorkerCtx ctx
        mySeniority = workerSeniority wctx w
        others = [ assignWorker a | a <- Set.toList (bySlot slot sched)
                 , assignWorker a /= w ]
    in any (\o -> workerSeniority wctx o > mySeniority) others

-- | Check the alternating-weekends-off rule.
-- A worker who worked the previous weekend may not work this weekend
-- unless they are weekend-only.
blockedByAlternateWeekend :: SchedulerContext -> WorkerId -> Slot -> Bool
blockedByAlternateWeekend ctx w slot =
    let dow = dayOfWeek (slotDate slot)
        isWeekendSlot = dow == Saturday || dow == Sunday
        wctx = schWorkerCtx ctx
        isWeekendOnlyWorker = Set.member w (wcWeekendOnly wctx)
        workedPrevWeekend = Set.member w (schPrevWeekendWorkers ctx)
    in isWeekendSlot && workedPrevWeekend && not isWeekendOnlyWorker

-- ---------------------------------------------------------------------
-- Phase 2: Retry unfilled with overtime (slot-level)
-- ---------------------------------------------------------------------

-- | Retry unfilled with perturbation support.
retryUnfilledSlotsP :: SchedulerContext -> Double -> [Double] -> Schedule
                    -> [Unfilled] -> (Schedule, [Unfilled], [Double])
retryUnfilledSlotsP _ _ ps sched [] = (sched, [], ps)
retryUnfilledSlotsP ctx mag ps sched (u@(Unfilled st t _kind) : rest) =
    let nCandidates = Set.size (schWorkers ctx)
        (used, ps') = splitAt nCandidates ps
    in case pickSlotWorkerP ctx True mag used t st sched of
        Nothing ->
            let (sched', rest', ps'') = retryUnfilledSlotsP ctx mag ps' sched rest
            in (sched', u : rest', ps'')
        Just w ->
            let sched' = assign (Assignment w st t) sched
            in retryUnfilledSlotsP ctx mag ps' sched' rest

-- ---------------------------------------------------------------------
-- Phase 3: Gap-fill (slot-level, for floaters and break coverage)
-- ---------------------------------------------------------------------

-- | Gap-fill with perturbation support.
gapFillP :: SchedulerContext -> Double -> [Double] -> Schedule
         -> [Unfilled] -> (Schedule, [Unfilled], [Double])
gapFillP _ _ ps sched [] = (sched, [], ps)
gapFillP ctx mag ps sched (u@(Unfilled st t _kind) : rest) =
    let nCandidates = Set.size (schWorkers ctx)
        (used, ps') = splitAt nCandidates ps
    in case pickSlotWorkerP ctx True mag used t st sched of
        Nothing ->
            let (sched', rest', ps'') = gapFillP ctx mag ps' sched rest
            in (sched', u : rest', ps'')
        Just w ->
            let sched' = assign (Assignment w st t) sched
            in gapFillP ctx mag ps' sched' rest

-- | Is a station closed for a given slot?
isClosed :: SchedulerContext -> Slot -> StationId -> Bool
isClosed ctx t st = Set.member (st, t) (schClosedSlots ctx)

-- ---------------------------------------------------------------------
-- Worker selection (shift-level)
-- ---------------------------------------------------------------------

-- | Pick the best worker with score perturbations.
-- Each candidate's score gets @magnitude * perturbation_i@ added.
pickShiftWorkerP :: SchedulerContext -> Bool -> Double -> [Double]
                 -> ShiftBlock -> StationId -> Schedule -> Maybe WorkerId
pickShiftWorkerP ctx allowOT magnitude perturbations block st sched =
    let activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
        candidates = filter (isShiftCandidate ctx allowOT st activeSlots sched)
                            (Set.toList (schWorkers ctx))
        scored = zipWith (\w p -> (w, scoreShiftWorker ctx block st sched w
                                      + magnitude * p))
                         candidates perturbations
        ranked = sortBy (flip (compare `on'` snd)) scored
    in case ranked of
        []        -> Nothing
        ((w,_):_) -> Just w
  where
    on' f g x y = f (g x) (g y)

-- | Is a worker a candidate for a shift at a station?
-- Must be qualified (or cross-training eligible), available on the day,
-- and able to work at least one slot.
isShiftCandidate :: SchedulerContext -> Bool -> StationId -> [Slot]
                 -> Schedule -> WorkerId -> Bool
isShiftCandidate ctx allowOT st slots sched w =
    let sctx = schSkillCtx ctx
        wctx = schWorkerCtx ctx
        skillOk = qualified sctx w st
                  || couldQualifyViaCrossTraining sctx wctx w st
    in skillOk
       && case slots of
           []    -> False
           (s:_) -> isWorkerAvailable w (slotDate s) (schAbsenceCtx ctx)
       && any (\s -> canAssignSlot ctx allowOT w st s sched) slots

-- | Score a worker for a shift at a station. Higher = better.
--
-- Factors:
--   1. Shift preference match (morning/afternoon/evening/weekend)
--   2. Station preference rank
--   3. Coverage: how many of the shift's slots the worker can fill
--   4. Remaining weekly hours capacity
--   5. Variety preference
scoreShiftWorker :: SchedulerContext -> ShiftBlock -> StationId -> Schedule
                 -> WorkerId -> Double
scoreShiftWorker ctx block st sched w =
    shiftPrefScore + stationPrefScore + coverageScore
    + capacityScore + varietyScore + crossTrainingScore
    + crossTrainingGoalScore + pairingScore
  where
    cfg = schConfig ctx
    wctx = schWorkerCtx ctx
    day = sbDay block
    shiftName = sdName (sbShift block)
    activeSlots = filter (\s -> not (isClosed ctx s st)) (sbSlots block)
    workableCount = length (filter (\s -> canAssignSlot ctx False w st s sched) activeSlots)

    shiftPrefScore =
        let prefs = Map.findWithDefault [] w (wcShiftPrefs wctx)
            shiftMatch = shiftName `elem` prefs
            weekendMatch = "weekend" `elem` prefs
                           && dayOfWeek day `elem` [Saturday, Sunday]
        in (if shiftMatch then cfgShiftPrefBonus cfg else 0)
           + (if weekendMatch then cfgWeekendPrefBonus cfg else 0)

    stationPrefScore = case stationPreferenceRank wctx w st of
        Just rank -> max 0 (cfgStationPrefBase cfg - fromIntegral rank)
        Nothing   -> 0

    coverageScore =
        let total = max 1 (length activeSlots)
            ratio = fromIntegral workableCount / fromIntegral total
        in ratio * cfgCoverageMultiplier cfg

    capacityScore = case workerMaxHours wctx w of
        Nothing   -> cfgNoLimitCapacity cfg
        Just maxH ->
            let current = workerWeeklyHours w day sched
                remaining = maxH - current
                ratio = if maxH > 0
                        then realToFrac remaining / realToFrac maxH
                        else 0
            in if remaining <= 0
               then cfgOverLimitPenalty cfg
               else ratio * cfgCapacityMultiplier cfg

    varietyScore =
        if workerPrefersVariety wctx w
        then let recent = recentStations w (addDays (-3) day) day sched
             in if Set.member st recent
                then cfgVarietyPenalty cfg
                else cfgVarietyBonus cfg
        else 0

    -- Cross-training: bonus when this worker's seniority differs from
    -- workers already assigned at the first slot of this shift block.
    crossTrainingScore =
        let bonus = cfgCrossTrainingBonus cfg
            mySeniority = workerSeniority wctx w
        in if bonus == 0 then 0
           else case activeSlots of
               [] -> 0
               (s:_) ->
                   let others = [ assignWorker a
                                | a <- Set.toList (bySlot s sched)
                                , assignWorker a /= w ]
                       hasDifferent = any (\o -> workerSeniority wctx o /= mySeniority) others
                   in if hasDifferent then bonus else 0

    -- Cross-training goal: bonus when this station matches the worker's
    -- cross-training goals and a mentor is present.
    crossTrainingGoalScore =
        let bonus = cfgCrossTrainingGoalBonus cfg
        in if bonus == 0 then 0
           else if couldQualifyViaCrossTraining (schSkillCtx ctx) wctx w st
                then case activeSlots of
                    [] -> 0
                    (s:_) -> if hasMentorAtSlot ctx w s sched then bonus else 0
                else 0

    -- Preferred pairing: bonus per preferred coworker at the first slot.
    pairingScore =
        let bonus = cfgPairingBonus cfg
        in if bonus == 0 then 0
           else case activeSlots of
               [] -> 0
               (s:_) ->
                   let othersAtSlot = Set.map assignWorker (bySlot s sched)
                       n = workerPrefersAt wctx w othersAtSlot
                   in fromIntegral n * bonus

-- ---------------------------------------------------------------------
-- Worker selection (slot-level, for gap-fill and retry)
-- ---------------------------------------------------------------------

-- | Pick the best worker for a single slot with score perturbations.
pickSlotWorkerP :: SchedulerContext -> Bool -> Double -> [Double]
                -> Slot -> StationId -> Schedule -> Maybe WorkerId
pickSlotWorkerP ctx allowOT magnitude perturbations t st sched =
    let candidates = filter (\w -> canAssignSlot ctx allowOT w st t sched)
                            (Set.toList (schWorkers ctx))
        scored = zipWith (\w p -> (w, scoreSlotWorker ctx t st sched w
                                      + magnitude * p))
                         candidates perturbations
        ranked = sortBy (flip (compare `on'` snd)) scored
    in case ranked of
        []        -> Nothing
        ((w,_):_) -> Just w
  where
    on' f g x y = f (g x) (g y)

-- | Score a worker for a single slot (used in gap-fill).
scoreSlotWorker :: SchedulerContext -> Slot -> StationId -> Schedule
                -> WorkerId -> Double
scoreSlotWorker ctx t st sched w =
    prefScore + capacityScore + varietyScore + multiStationScore
    + crossTrainingScore + crossTrainingGoalScore + pairingScore
  where
    cfg = schConfig ctx
    wctx = schWorkerCtx ctx

    prefScore = case stationPreferenceRank wctx w st of
        Just rank -> max 0 (cfgStationPrefBase cfg - fromIntegral rank)
        Nothing   -> 0

    capacityScore = case workerMaxHours wctx w of
        Nothing   -> cfgNoLimitCapacity cfg
        Just maxH ->
            let current = workerWeeklyHours w (slotDate t) sched
                remaining = maxH - current
                ratio = if maxH > 0
                        then realToFrac remaining / realToFrac maxH
                        else 0
            in if remaining <= 0
               then cfgOverLimitPenalty cfg
               else ratio * cfgCapacityMultiplier cfg

    varietyScore =
        if workerPrefersVariety wctx w
        then let recent = recentStations w (addDays (-3) (slotDate t)) (slotDate t) sched
             in if Set.member st recent
                then cfgVarietyPenalty cfg
                else cfgVarietyBonus cfg
        else 0

    multiStationScore =
        if not (Set.null (byWorkerSlot w t sched))
        then cfgMultiStationBonus cfg
        else 0

    -- Cross-training: bonus when this worker's seniority differs from
    -- workers already assigned at this slot.
    crossTrainingScore =
        let bonus = cfgCrossTrainingBonus cfg
            mySeniority = workerSeniority wctx w
        in if bonus == 0 then 0
           else let others = [ assignWorker a
                             | a <- Set.toList (bySlot t sched)
                             , assignWorker a /= w ]
                    hasDifferent = any (\o -> workerSeniority wctx o /= mySeniority) others
                in if hasDifferent then bonus else 0

    -- Cross-training goal: bonus when this station matches the worker's
    -- cross-training goals and a mentor is present.
    crossTrainingGoalScore =
        let bonus = cfgCrossTrainingGoalBonus cfg
        in if bonus == 0 then 0
           else if couldQualifyViaCrossTraining (schSkillCtx ctx) wctx w st
                   && hasMentorAtSlot ctx w t sched
                then bonus
                else 0

    -- Preferred pairing: bonus per preferred coworker at this slot.
    pairingScore =
        let bonus = cfgPairingBonus cfg
        in if bonus == 0 then 0
           else let othersAtSlot = Set.map assignWorker (bySlot t sched)
                    n = workerPrefersAt wctx w othersAtSlot
                in fromIntegral n * bonus

-- ---------------------------------------------------------------------
-- Overtime computation
-- ---------------------------------------------------------------------

-- | Compute overtime hours per worker.
computeOvertime :: SchedulerContext -> Schedule -> Map WorkerId DiffTime
computeOvertime ctx sched =
    Map.foldlWithKey' (\acc w maxH ->
        let weekStarts = uniqueWeekStarts w sched
            ot = sum [max 0 (workerWeeklyHours w ws sched - maxH) | ws <- weekStarts]
        in if ot > 0 then Map.insert w ot acc else acc)
        Map.empty
        (wcMaxWeeklyHours (schWorkerCtx ctx))

-- | Find all distinct week start dates for a worker's assignments.
uniqueWeekStarts :: WorkerId -> Schedule -> [Day]
uniqueWeekStarts w sched =
    let assignments = byWorker w sched
        weeks = Set.map (slotWeek . slotDate . assignSlot) assignments
    in Set.toList weeks

-- ---------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------

-- Workers
schw_alice, schw_bob, schw_carol, schw_dave :: WorkerId
schw_alice = WorkerId 1   -- management (implies cooking, prep)
schw_bob   = WorkerId 2   -- cooking (implies prep)
schw_carol = WorkerId 3   -- prep only
schw_dave  = WorkerId 4   -- cooking (implies prep)

-- Skills
schsk_prep, schsk_cooking, schsk_management :: SkillId
schsk_prep       = SkillId 1
schsk_cooking    = SkillId 2
schsk_management = SkillId 3

-- Stations
schst_grill, schst_prep_table :: StationId
schst_grill      = StationId 1   -- requires cooking
schst_prep_table = StationId 2   -- requires prep

schMkSlot :: Day -> Int -> Slot
schMkSlot d h = Slot d (TimeOfDay h 0 0) 3600

-- | A single slot on Monday at 9am.
schMondaySlot :: Slot
schMondaySlot = schMkSlot (fromGregorian 2026 5 4) 9

-- | Two slots on the same day (9am and 10am).
schTwoSlots :: [Slot]
schTwoSlots = [ schMkSlot (fromGregorian 2026 5 4) 9
              , schMkSlot (fromGregorian 2026 5 4) 10
              ]

-- | Five slots across the week (Mon-Fri at 9am).
schWeekSlots :: [Slot]
schWeekSlots = [ schMkSlot (fromGregorian 2026 5 (4 + i)) 9 | i <- [0..4] ]

-- | Basic skill context: grill requires cooking, prep_table requires prep.
schBasicSkillCtx :: SkillContext
schBasicSkillCtx = SkillContext
    { scWorkerSkills = Map.fromList
        [ (schw_alice, Set.singleton schsk_management)
        , (schw_bob,   Set.singleton schsk_cooking)
        , (schw_carol, Set.singleton schsk_prep)
        , (schw_dave,  Set.singleton schsk_cooking)
        ]
    , scStationRequires = Map.fromList
        [ (schst_grill,      Set.singleton schsk_cooking)
        , (schst_prep_table, Set.singleton schsk_prep)
        ]
    , scSkillImplies = Map.fromList
        [ (schsk_management, Set.singleton schsk_cooking)
        , (schsk_cooking,    Set.singleton schsk_prep)
        ]
    , scAllStations = Set.fromList [schst_grill, schst_prep_table]
    , scStationHours = Map.empty
    , scMultiStationHours = Map.empty
    }

-- | Worker context: everyone has generous hours, no overtime issues.
schRelaxedWorkerCtx :: WorkerContext
schRelaxedWorkerCtx = WorkerContext
    { wcMaxWeeklyHours = Map.fromList
        [ (schw_alice, 40 * 3600)
        , (schw_bob,   40 * 3600)
        , (schw_carol, 40 * 3600)
        , (schw_dave,  40 * 3600)
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

-- | Worker context where bob has very limited hours (1 hour/week).
schTightHoursWorkerCtx :: WorkerContext
schTightHoursWorkerCtx = schRelaxedWorkerCtx
    { wcMaxWeeklyHours = Map.fromList
        [ (schw_alice, 40 * 3600)
        , (schw_bob,   1 * 3600)
        , (schw_carol, 40 * 3600)
        , (schw_dave,  40 * 3600)
        ]
    }

-- | Worker context where bob has tight hours but opts in to overtime.
schOvertimeWorkerCtx :: WorkerContext
schOvertimeWorkerCtx = schTightHoursWorkerCtx
    { wcOvertimeOptIn = Set.singleton schw_bob
    }

-- | Worker context with station preferences.
schPrefWorkerCtx :: WorkerContext
schPrefWorkerCtx = schRelaxedWorkerCtx
    { wcStationPrefs = Map.fromList
        [ (schw_alice, [schst_grill, schst_prep_table])
        , (schw_bob,   [schst_prep_table, schst_grill])
        ]
    }

-- | Worker context where bob prefers variety.
schVarietyWorkerCtx :: WorkerContext
schVarietyWorkerCtx = schRelaxedWorkerCtx
    { wcPrefersVariety = Set.singleton schw_bob
    }

schAllWorkers :: Set WorkerId
schAllWorkers = Set.fromList [schw_alice, schw_bob, schw_carol, schw_dave]

schMkCtx :: SkillContext -> WorkerContext -> AbsenceContext -> [Slot] -> Set WorkerId -> SchedulerContext
schMkCtx sk wk ac slots workers = SchedulerContext sk wk ac slots workers Set.empty [] Set.empty defaultConfig

spec :: Spec
spec = do
    describe "buildSchedule basics" $ do
        it "fills all positions when enough qualified workers" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                result = buildSchedule ctx
            srUnfilled result `shouldBe` []

        it "creates assignments for every station at every slot" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                result = buildSchedule ctx
                sched = srSchedule result
            scheduleSize sched `shouldSatisfy` (>= 2)

        it "empty slots list produces empty schedule" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [] schAllWorkers
                result = buildSchedule ctx
            srSchedule result `shouldBe` emptySchedule
            srUnfilled result `shouldBe` []

        it "no workers produces all unfilled" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] Set.empty
                result = buildSchedule ctx
            length (srUnfilled result) `shouldBe` 2

    describe "Skill-based assignment" $ do
        it "does not assign unqualified workers to stations" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext schWeekSlots schAllWorkers
                result = buildSchedule ctx
                sched = srSchedule result
                carolAssignments = byWorker schw_carol sched
                carolStations = Set.map assignStation carolAssignments
            carolStations `shouldSatisfy` (not . Set.member schst_grill)

        it "workers with implied skills can fill higher stations" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot]
                            (Set.singleton schw_alice)
                result = buildSchedule ctx
                sched = srSchedule result
                aliceAtGrill = Set.filter
                    (\a -> assignStation a == schst_grill)
                    (byWorker schw_alice sched)
            Set.size aliceAtGrill `shouldBe` 1

    describe "Unfilled positions" $ do
        it "reports unfilled when not enough qualified workers" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot]
                            (Set.singleton schw_carol)
                result = buildSchedule ctx
            any (\u -> unfilledStation u == schst_grill) (srUnfilled result)
                `shouldBe` True

        it "carol fills prep_table but not grill" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot]
                            (Set.singleton schw_carol)
                result = buildSchedule ctx
                sched = srSchedule result
            Set.size (byWorkerSlot schw_carol schMondaySlot sched) `shouldBe` 1
            any (\u -> unfilledStation u == schst_grill) (srUnfilled result)
                `shouldBe` True

    describe "Hours and overtime" $ do
        it "no overtime when all workers within limits" $ do
            let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                result = buildSchedule ctx
            srOvertime result `shouldBe` Map.empty

        it "does not assign worker beyond their hours in phase 1" $ do
            let ctx = schMkCtx schBasicSkillCtx schTightHoursWorkerCtx emptyAbsenceContext schTwoSlots schAllWorkers
                result = buildSchedule ctx
                sched = srSchedule result
                bobAssignments = byWorker schw_bob sched
                bobHours = Set.foldl' (\acc a -> acc + slotDuration (assignSlot a)) 0 bobAssignments
            bobHours `shouldSatisfy` (<= 1 * 3600)

        it "uses overtime-eligible workers in phase 2 when needed" $ do
            let ctx = schMkCtx schBasicSkillCtx schOvertimeWorkerCtx emptyAbsenceContext schTwoSlots
                            (Set.fromList [schw_bob, schw_carol])
                result = buildSchedule ctx
            srUnfilled result `shouldBe` []

        it "reports overtime when it occurs" $ do
            let ctx = schMkCtx schBasicSkillCtx schOvertimeWorkerCtx emptyAbsenceContext schTwoSlots
                            (Set.fromList [schw_bob, schw_carol])
                result = buildSchedule ctx
            case Map.lookup schw_bob (srOvertime result) of
                Nothing -> expectationFailure "expected bob to have overtime"
                Just ot -> ot `shouldSatisfy` (> 0)

    describe "Worker preferences" $ do
        it "prefers worker's preferred station" $ do
            let ctx = schMkCtx schBasicSkillCtx schPrefWorkerCtx emptyAbsenceContext [schMondaySlot]
                            (Set.fromList [schw_alice, schw_bob])
                result = buildSchedule ctx
                sched = srSchedule result
                aliceStations = Set.map assignStation (byWorker schw_alice sched)
                bobStations = Set.map assignStation (byWorker schw_bob sched)
            aliceStations `shouldSatisfy` Set.member schst_grill
            bobStations `shouldSatisfy` Set.member schst_prep_table

    describe "Variety preference" $ do
        it "variety-preferring worker avoids repeat stations across days" $ do
            let slots = [ schMkSlot (fromGregorian 2026 5 (4 + i)) 9 | i <- [0..2] ]
                ctx = schMkCtx schBasicSkillCtx schVarietyWorkerCtx emptyAbsenceContext slots schAllWorkers
                result = buildSchedule ctx
                sched = srSchedule result
                bobStations = Set.map assignStation (byWorker schw_bob sched)
            Set.size bobStations `shouldSatisfy` (> 1)

    describe "scoreSlotWorker" $ do
        it "scores higher for preferred station" $ do
            let ctx = schMkCtx schBasicSkillCtx schPrefWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                grillScore = scoreSlotWorker ctx schMondaySlot schst_grill emptySchedule schw_alice
                prepScore  = scoreSlotWorker ctx schMondaySlot schst_prep_table emptySchedule schw_alice
            grillScore `shouldSatisfy` (> prepScore)

        it "scores higher for worker with more remaining capacity" $ do
            let ctx = schMkCtx schBasicSkillCtx schTightHoursWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                sched = foldl (\s t -> assign (Assignment schw_bob schst_grill t) s) emptySchedule
                            [schMkSlot (fromGregorian 2026 5 4) 10]
                aliceScore = scoreSlotWorker ctx schMondaySlot schst_grill sched schw_alice
                bobScore   = scoreSlotWorker ctx schMondaySlot schst_grill sched schw_bob
            aliceScore `shouldSatisfy` (> bobScore)

        it "penalizes repeat stations for variety-preferring worker" $ do
            let ctx = schMkCtx schBasicSkillCtx schVarietyWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                sched = assign (Assignment schw_bob schst_grill (schMkSlot (fromGregorian 2026 5 3) 9))
                            emptySchedule
                grillScore = scoreSlotWorker ctx schMondaySlot schst_grill sched schw_bob
                prepScore  = scoreSlotWorker ctx schMondaySlot schst_prep_table sched schw_bob
            prepScore `shouldSatisfy` (> grillScore)

    describe "Absence integration" $ do
        it "excludes workers on approved absence from scheduling" $ do
            let vacType = AbsenceTypeId 1
                -- alice is on vacation May 4
                (actx, aid) = requestAbsence schw_alice vacType
                                  (fromGregorian 2026 5 4) (fromGregorian 2026 5 4)
                                  emptyAbsenceContext
                    { acTypes = Map.singleton vacType
                        (Domain.Absence.AbsenceType "Vacation" True)
                    , acYearlyAllowance = Map.singleton (schw_alice, vacType) 10
                    }
            case approveAbsence aid actx of
                Nothing -> expectationFailure "approveAbsence returned Nothing"
                Just actx' -> do
                    let ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx actx' [schMondaySlot] schAllWorkers
                        result = buildSchedule ctx
                        sched = srSchedule result
                        aliceAssignments = byWorker schw_alice sched
                    -- alice should have no assignments on May 4
                    Set.size aliceAssignments `shouldBe` 0

    describe "buildScheduleFrom (seed schedule)" $ do
        it "preserves pinned assignments" $ do
            let pinned = assign (Assignment schw_carol schst_prep_table schMondaySlot) emptySchedule
                ctx = schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers
                result = buildScheduleFrom pinned ctx
                sched = srSchedule result
                carolSlot = byWorkerSlot schw_carol schMondaySlot sched
            Set.size carolSlot `shouldBe` 1
            Set.map assignStation carolSlot `shouldBe` Set.singleton schst_prep_table

    describe "Closed station/slot pairs" $ do
        it "closed station is not staffed and not reported as unfilled" $ do
            let ctx = (schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers)
                        { schClosedSlots = Set.singleton (schst_grill, schMondaySlot) }
                result = buildSchedule ctx
                sched = srSchedule result
                grillAssignments = Set.filter (\a -> assignStation a == schst_grill) (unSchedule sched)
            Set.size grillAssignments `shouldBe` 0
            srUnfilled result `shouldBe` []

        it "other stations are still staffed when one is closed" $ do
            let ctx = (schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext [schMondaySlot] schAllWorkers)
                        { schClosedSlots = Set.singleton (schst_grill, schMondaySlot) }
                result = buildSchedule ctx
                sched = srSchedule result
                prepAssignments = Set.filter (\a -> assignStation a == schst_prep_table) (unSchedule sched)
            Set.size prepAssignments `shouldSatisfy` (>= 1)

    describe "Alternating weekends off" $ do
        it "blocks a worker who worked the previous weekend" $ do
            -- Saturday slot; bob worked last weekend
            let satSlot = schMkSlot (fromGregorian 2026 5 9) 9  -- Saturday
                ctx = (schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext
                        [satSlot] (Set.fromList [schw_bob, schw_carol]))
                    { schPrevWeekendWorkers = Set.singleton schw_bob }
                result = buildSchedule ctx
                sched = srSchedule result
                bobAssignments = byWorker schw_bob sched
            -- bob should NOT be assigned (he worked last weekend)
            Set.size bobAssignments `shouldBe` 0

        it "allows weekend-only workers despite previous weekend" $ do
            let satSlot = schMkSlot (fromGregorian 2026 5 9) 9
                weekendOnlyCtx = schRelaxedWorkerCtx
                    { wcWeekendOnly = Set.singleton schw_bob }
                ctx = (schMkCtx schBasicSkillCtx weekendOnlyCtx emptyAbsenceContext
                        [satSlot] (Set.fromList [schw_bob, schw_carol]))
                    { schPrevWeekendWorkers = Set.singleton schw_bob }
                result = buildSchedule ctx
                sched = srSchedule result
                bobAssignments = byWorker schw_bob sched
            -- bob IS weekend-only, so he should still be assigned
            Set.size bobAssignments `shouldSatisfy` (>= 1)

        it "does not block workers on weekdays" $ do
            -- Monday slot; bob worked last weekend — should still work Monday
            let ctx = (schMkCtx schBasicSkillCtx schRelaxedWorkerCtx emptyAbsenceContext
                        [schMondaySlot] (Set.fromList [schw_bob, schw_carol]))
                    { schPrevWeekendWorkers = Set.singleton schw_bob }
                result = buildSchedule ctx
                sched = srSchedule result
                bobAssignments = byWorker schw_bob sched
            Set.size bobAssignments `shouldSatisfy` (>= 1)
