-- | One place that assembles a 'SchedulerContext' from the repository.
--
-- 'Service.Draft' and 'Service.DraftValidation' each built their own, and the two
-- disagreed about the fields that decide whether an assignment's hours are legal.
-- Every such disagreement found so far has been the validator reporting a
-- violation for something the scheduler was entitled to do; see ADR 0005 and
-- ADR 0006. A single loader is the structural fix.
--
-- What it does /not/ decide is the two fields the two callers legitimately
-- differ on — the slots to fill and the closed station-slots. A caller that
-- builds fills them in; a caller that judges leaves them empty.
module Service.Context
    ( loadValidationContext
    , loadValidationContextExcluding
    , calendarHoursOutside
    , payPeriodChunks
      -- * Building over a range
    , BuildPlan(..)
    , loadBuildPlan
    , stripLookBack
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, DiffTime, addDays)

import Domain.Types
    ( WorkerId, Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler (SchedulerContext(..), ScheduleResult(..), filterExemptCalendarHours)
import Domain.Worker (WorkerContext)
import Domain.Calendar (generateDateRangeSlots, defaultHours)
import Domain.Skill (stationClosedSlots)
import Domain.PayPeriod (defaultPayPeriodConfig, payPeriodBounds)
import Repo.Types (Repository(..))
import qualified Service.Calendar as Cal

-- | Assemble the context for judging or building a schedule over an inclusive
-- date range.
--
-- 'schPeriodBounds' is the /pay period/ containing the range's start, never the
-- range itself: the pay period is by definition the interval hour limits are
-- measured over, and it is independent of whatever dates a draft happens to
-- cover. 'schCalendarHours' counts the committed calendar inside that pay period
-- but /outside/ the range being judged, so the caller's own schedule supplies the
-- rest and nothing is counted twice.
--
-- 'schSlots', 'schClosedSlots' and 'schWorkers' come back empty. A caller that
-- needs slots fills them in; a caller that judges existing assignments does
-- not need them.
loadValidationContext
    :: Repository
    -> (Day, Day)              -- ^ Inclusive range being judged or built.
    -> IO SchedulerContext
loadValidationContext repo range =
    loadValidationContextExcluding repo range range

-- | 'loadValidationContext', but excluding a wider range than the one being
--   judged from 'schCalendarHours'.
--
--   The validator and the generator both join a seven-day calendar look-back
--   onto the schedule they work over, so that rest, consecutive-hour and
--   alternating-weekend rules can see across the range's start. Those look-back
--   days are then /in the schedule/, and if they also fall inside the pay period
--   they must not be counted again through the calendar hours map — which is
--   exactly what happened when the exclusion was the range alone: a mid-period
--   draft charged the period's earlier days twice, and a worker exactly at their
--   cap was reported over it. The caller that joins the look-back passes the
--   look-back's start here.
loadValidationContextExcluding
    :: Repository
    -> (Day, Day)              -- ^ Inclusive range being judged or built.
    -> (Day, Day)              -- ^ Inclusive range whose calendar hours the
                               --   caller supplies itself, so they are excluded.
    -> IO SchedulerContext
loadValidationContextExcluding repo (from, _to) excluded = do
    skillCtx   <- repoLoadSkillCtx repo
    workerCtx  <- repoLoadWorkerCtx repo
    absenceCtx <- repoLoadAbsenceCtx repo
    cfg        <- repoLoadSchedulerConfig repo
    shifts     <- repoLoadShifts repo
    mPpc       <- repoLoadPayPeriodConfig repo
    let ppc = maybe defaultPayPeriodConfig id mPpc
        bounds@(periodStart, periodEnd) = payPeriodBounds ppc from
    calHrs <- calendarHoursOutside repo workerCtx (periodStart, periodEnd) excluded
    return SchedulerContext
        { schSkillCtx    = skillCtx
        , schWorkerCtx   = workerCtx
        , schAbsenceCtx  = absenceCtx
        , schSlots       = []
        , schWorkers     = Set.empty
        , schClosedSlots = Set.empty
        , schShifts      = shifts
        , schConfig      = cfg
        , schPeriodBounds = bounds
        , schCalendarHours = calHrs
        }

-- | An inclusive date range cut at pay-period boundaries, in order.
--
-- A 'SchedulerContext' holds one pay period, the one containing the range's
-- start, and every hour rule measures against it. An assignment in a later
-- period therefore adds nothing to the count and is judged on the first
-- period's total, which is the wrong period and usually the wrong answer.
-- Anything judging a range that may span periods judges each chunk with its own
-- context. The problem view's request covers the current period and the next,
-- so it always spans two.
payPeriodChunks :: Repository -> (Day, Day) -> IO [(Day, Day)]
payPeriodChunks repo (from, to) = do
    mPpc <- repoLoadPayPeriodConfig repo
    let ppc = maybe defaultPayPeriodConfig id mPpc
        go d | d > to = []
             | otherwise =
                 let (_, endExcl) = payPeriodBounds ppc d
                     chunkTo = min to (addDays (-1) endExcl)
                 in (d, chunkTo) : go (addDays 1 chunkTo)
    return (go from)

-- | Everything a build over an inclusive date range starts from.
--
-- Four callers build or re-build a schedule over a range — generating a draft,
-- diagnosing a draft, diagnosing a calendar slice, and a what-if session — and
-- three of them used to assemble this by hand with the range as the pay period,
-- no committed hours and no look-back, so `draft diagnose` filled the gaps it
-- was asked to explain and called the draft fully staffed. One plan, built here.
data BuildPlan = BuildPlan
    { bpFrom         :: !Day
      -- ^ The range's first day; everything before it in a result is look-back.
    , bpLookBackFrom :: !Day
      -- ^ Seven days before 'bpFrom'.
    , bpLookBack     :: !Schedule
      -- ^ The committed calendar over those seven days. Joins every seed so the
      -- rules that look across days see across the range's start; stripped from
      -- results with 'stripLookBack'.
    , bpContexts     :: ![SchedulerContext]
      -- ^ One per pay period the range touches, in order, each with its slots,
      -- closed station-slots and workers filled in, and with the look-back and
      -- every earlier period excluded from its calendar hours because the seed
      -- already holds them.
    }

-- | The plan for building over a range with the given workers. See 'BuildPlan'.
loadBuildPlan :: Repository -> Set.Set WorkerId -> (Day, Day) -> IO BuildPlan
loadBuildPlan repo workers (from, to) = do
    let lookBackFrom = addDays (-7) from
    lookBack <- Cal.loadCalendarSlice repo lookBackFrom (addDays (-1) from)
    chunks <- payPeriodChunks repo (from, to)
    ctxs <- mapM (contextFor lookBackFrom) chunks
    return BuildPlan
        { bpFrom = from, bpLookBackFrom = lookBackFrom
        , bpLookBack = lookBack, bpContexts = ctxs }
  where
    contextFor lookBackFrom chunk@(cFrom, cTo) = do
        let slots = generateDateRangeSlots defaultHours cFrom cTo Set.empty
        base <- loadValidationContextExcluding repo chunk (lookBackFrom, cTo)
        return base
            { schSlots       = slots
            , schWorkers     = workers
            , schClosedSlots = stationClosedSlots (schSkillCtx base) slots
            }

-- | Drop the look-back from a result built over a plan: it was context, not
-- material, and nothing downstream should save, show or count it.
stripLookBack :: BuildPlan -> ScheduleResult -> ScheduleResult
stripLookBack plan r =
    r { srSchedule = Schedule (Set.filter inRange (unSchedule (srSchedule r))) }
  where
    inRange a = slotDate (assignSlot a) >= bpFrom plan

-- | Committed calendar hours per worker inside a pay period but outside a given
-- range, with exempt workers filtered out.
--
-- The exclusion is the point. Whoever asks is about to supply their own hours for
-- that range — a draft's assignments, or the calendar slice itself — and counting
-- the calendar's copy as well would charge those hours twice. The pay-period
-- bounds are half-open (end exclusive), matching 'payPeriodBounds'; the excluded
-- range is inclusive, matching how every date range in this codebase is spelled.
calendarHoursOutside
    :: Repository
    -> WorkerContext
    -> (Day, Day)              -- ^ Pay period: start inclusive, end exclusive.
    -> (Day, Day)              -- ^ Range to exclude, both ends inclusive.
    -> IO (Map WorkerId DiffTime)
calendarHoursOutside repo wctx (periodStart, periodEnd) (exFrom, exTo) = do
    -- The pay period's end is exclusive, and loadCalendarSlice is inclusive.
    calSched <- Cal.loadCalendarSlice repo periodStart (addDays (-1) periodEnd)
    let outside a =
            let d = slotDate (assignSlot a)
            in d < exFrom || d > exTo
        assignments = filter outside (Set.toList (unSchedule calSched))
        -- Group by (worker, slot) so multi-station assignments count once.
        uniqueSlots = Set.fromList [(assignWorker a, assignSlot a) | a <- assignments]
        raw = Set.foldl'
            (\acc (w, s) -> Map.insertWith (+) w (slotDuration s) acc)
            Map.empty uniqueSlots
    return (filterExemptCalendarHours wctx raw)
