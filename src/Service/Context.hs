-- | One place that assembles a 'SchedulerContext' from the repository.
--
-- 'Service.Draft' and 'Service.DraftValidation' each built their own, and the two
-- disagreed about the fields that decide whether an assignment's hours are legal.
-- Every such disagreement found so far has been the validator reporting a
-- violation for something the scheduler was entitled to do; see ADR 0005 and
-- ADR 0006. A single loader is the structural fix.
--
-- What it does /not/ decide is the three fields the two callers legitimately
-- differ on — the slots to fill, the closed station-slots, and the
-- previous-weekend workers. Those are arguments, because pretending they are the
-- same would be the opposite error.
module Service.Context
    ( loadValidationContext
    , calendarHoursOutside
    ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, DiffTime, addDays)

import Domain.Types
    ( WorkerId, Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler (SchedulerContext(..), filterExemptCalendarHours)
import Domain.Worker (WorkerContext)
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
-- 'schSlots', 'schClosedSlots' and 'schWorkers' come back empty and
-- 'schPrevWeekendWorkers' comes back as given. A caller that needs slots fills
-- them in; a caller that judges existing assignments does not need them.
loadValidationContext
    :: Repository
    -> (Day, Day)              -- ^ Inclusive range being judged or built.
    -> Set.Set WorkerId        -- ^ Workers who worked the previous weekend.
    -> IO SchedulerContext
loadValidationContext repo (from, to) prevWeekendWorkers = do
    skillCtx   <- repoLoadSkillCtx repo
    workerCtx  <- repoLoadWorkerCtx repo
    absenceCtx <- repoLoadAbsenceCtx repo
    cfg        <- repoLoadSchedulerConfig repo
    shifts     <- repoLoadShifts repo
    mPpc       <- repoLoadPayPeriodConfig repo
    let ppc = maybe defaultPayPeriodConfig id mPpc
        bounds@(periodStart, periodEnd) = payPeriodBounds ppc from
    calHrs <- calendarHoursOutside repo workerCtx (periodStart, periodEnd) (from, to)
    return SchedulerContext
        { schSkillCtx    = skillCtx
        , schWorkerCtx   = workerCtx
        , schAbsenceCtx  = absenceCtx
        , schSlots       = []
        , schWorkers     = Set.empty
        , schClosedSlots = Set.empty
        , schShifts      = shifts
        , schPrevWeekendWorkers = prevWeekendWorkers
        , schConfig      = cfg
        , schPeriodBounds = bounds
        , schCalendarHours = calHrs
        }

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
