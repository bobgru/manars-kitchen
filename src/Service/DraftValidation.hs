module Service.DraftValidation
    ( -- * Types
      DraftViolation(..)
      -- * Validation
    , validateAssignment
    , buildLookBackContext
      -- * Validating a draft against the calendar
      --
      -- $draftValidation
    , isDraftStale
    , calendarReplacedUnder
    , computeDraftViolations
    , pruneDraftViolations
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (DayOfWeek(..), addDays, dayOfWeek)

import Domain.Types
    ( WorkerId
    , Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Schedule (bySlot)
import Domain.Scheduler (SchedulerContext(..), blockedByAlternateWeekend)
import Domain.Skill (qualified)
import Domain.Worker
    ( violatesRestPeriod, needsBreak
    , wouldBeOvertime, wouldExceedDailyRegular
    , workerAvoidsAt
    )
import Domain.Absence (isWorkerAvailable)
import Repo.Types (Repository(..), DraftInfo(..), CalendarCommit(..))
import qualified Service.Calendar as Cal

-- | A record of a constraint violation that caused an assignment to be removed.
data DraftViolation = DraftViolation
    { dvAssignment    :: !Assignment
    , dvConstraint    :: !String
    , dvReason        :: !String
    } deriving (Show, Eq)

-- | Check a single assignment against all hard constraints.
-- Returns Just a violation if any constraint is violated, Nothing if valid.
validateAssignment :: SchedulerContext -> Assignment -> Schedule -> Maybe DraftViolation
validateAssignment ctx a sched
    | not skillOk =
        Just (DraftViolation a "skill qualification" "worker not qualified for station")
    | not (isWorkerAvailable w (slotDate slot) (schAbsenceCtx ctx)) =
        Just (DraftViolation a "absence conflict" "worker has approved absence on this date")
    | blockedByAlternateWeekend ctx w slot =
        Just (DraftViolation a "alternating weekends"
            "worked previous weekend in calendar")
    | wouldBeOvertime (schWorkerCtx ctx) (schPeriodBounds ctx) (schCalendarHours ctx) sched a =
        Just (DraftViolation a "period hours" "would exceed per-period hour limit")
    | wouldExceedDailyRegular (schConfig ctx) a sched =
        Just (DraftViolation a "daily hours" "would exceed daily hour limit")
    | violatesRestPeriod (schConfig ctx) w slot sched =
        Just (DraftViolation a "rest period"
            "insufficient rest since previous day's last assignment")
    | needsBreak (schConfig ctx) w slot sched =
        Just (DraftViolation a "consecutive hours" "exceeds maximum consecutive hours")
    | avoidBlocked =
        Just (DraftViolation a "avoid-pairing" "paired with avoided coworker")
    | otherwise = Nothing
  where
    w    = assignWorker a
    slot = assignSlot a
    sctx = schSkillCtx ctx
    wctx = schWorkerCtx ctx
    skillOk = qualified sctx w (assignStation a)
    avoidBlocked =
        let othersAtSlot = Set.map assignWorker (bySlot slot sched)
            withoutSelf  = Set.delete w othersAtSlot
        in workerAvoidsAt wctx w withoutSelf

-- | Build previous-weekend workers set from a calendar look-back schedule.
-- The look-back covers 7 days before the draft start date.
buildLookBackContext :: Schedule -> Set.Set WorkerId
buildLookBackContext (Schedule as) =
    Set.fromList
        [ assignWorker a
        | a <- Set.toList as
        , let dow = dayOfWeek (slotDate (assignSlot a))
        , dow == Saturday || dow == Sunday
        ]

-- $draftValidation
--
-- Validating a draft against the calendar is three separable things, and
-- callers want different subsets of them:
--
-- * 'isDraftStale' — has the calendar moved since this draft was last
--   validated?
-- * 'calendarReplacedUnder' — has the calendar moved /inside this draft's own
--   date range/, and what replaced it?
-- * 'computeDraftViolations' — which of the draft's assignments no longer
--   hold? A read: no writes, and no staleness gate.
-- * 'pruneDraftViolations' — the gate, the computation, and the removal.
--
-- Anything that reports violations to a reader wants 'computeDraftViolations'.
-- Only a caller that intends to change the draft wants 'pruneDraftViolations'.

-- | Has the calendar moved since this draft was last validated? True when any
-- calendar commit carries a timestamp after the draft's last-validated
-- timestamp.
--
-- Takes a loaded 'DraftInfo' rather than an id so a caller that already has the
-- draft does not read it again.
isDraftStale :: Repository -> DraftInfo -> IO Bool
isDraftStale repo draft =
    not . null <$> repoCalendarCommitsAfter repo (diLastValidatedAt draft)

-- | The calendar commits that replaced part of this draft's /own/ date range
-- since it was last validated, newest first.
--
-- This is the blind spot 'isDraftStale' and 'computeDraftViolations' share.
-- Validation looks back at the seven days /before/ a draft starts, because that
-- is what the alternating-weekend and rest-period rules need; it never looks at
-- the calendar inside the range, since the draft is about to overwrite it. Once
-- drafts may overlap, that is exactly where the surprise lives: a sibling draft
-- committed over the same week leaves this draft's assignments individually
-- valid and collectively built on a calendar that no longer exists.
--
-- Reporting is all this does. Nothing is pruned, because nothing here is
-- necessarily wrong — the admin has to decide whether their experiment still
-- means anything now that the baseline moved.
calendarReplacedUnder :: Repository -> DraftInfo -> IO [CalendarCommit]
calendarReplacedUnder repo draft = do
    commits <- repoCalendarCommitsAfter repo (diLastValidatedAt draft)
    return (filter overlapsDraft commits)
  where
    overlapsDraft c =
        ccDateFrom c <= diDateTo draft && ccDateTo c >= diDateFrom draft

-- | Which of a draft's assignments violate a hard constraint against the
-- current calendar? Writes nothing, and does /not/ gate on staleness: every
-- call validates whatever the draft holds right now.
--
-- Returns @[]@ for a draft that does not exist and for one with no
-- assignments.
computeDraftViolations :: Repository -> Int -> IO [DraftViolation]
computeDraftViolations repo draftId = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing    -> return []
        Just draft -> snd <$> validateDraft repo draft

-- | Validate a draft against the current calendar and remove the assignments
-- that no longer hold, returning what was removed.
--
-- A no-op returning @[]@ unless the draft is stale — re-validating a draft the
-- calendar has not moved under would find nothing new. Once past that gate the
-- last-validated timestamp is bumped whether or not anything was removed, so a
-- clean pass is not repeated on the next open.
pruneDraftViolations :: Repository -> Int -> IO [DraftViolation]
pruneDraftViolations repo draftId = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return []
        Just draft -> do
            stale <- isDraftStale repo draft
            if not stale
                then return []
                else do
                    (draftSched, violations) <- validateDraft repo draft
                    if null violations
                        then return ()
                        else do
                            let violatingAssigns =
                                    Set.fromList (map dvAssignment violations)
                                cleanedSched = Schedule (Set.difference
                                    (unSchedule draftSched) violatingAssigns)
                            repoSaveDraftAssignments repo draftId cleanedSched
                    repoUpdateDraftValidatedAt repo draftId
                    return violations

-- | The shared body of 'computeDraftViolations' and 'pruneDraftViolations':
-- validate every assignment the draft holds against a calendar look-back
-- window. Returns the draft's assignments alongside the violations so a caller
-- that prunes does not load them a second time.
validateDraft :: Repository -> DraftInfo -> IO (Schedule, [DraftViolation])
validateDraft repo draft = do
    draftSched <- repoLoadDraftAssignments repo (diId draft)
    let draftAssignments = Set.toList (unSchedule draftSched)
    if null draftAssignments
        then return (draftSched, [])
        else do
            -- Load look-back context (7 days before draft start)
            let lookBackStart = addDays (-7) (diDateFrom draft)
                lookBackEnd   = addDays (-1) (diDateFrom draft)
            lookBackSched <- Cal.loadCalendarSlice repo lookBackStart lookBackEnd

            -- Build the SchedulerContext for validation
            let prevWeekendWorkers = buildLookBackContext lookBackSched
            skillCtx   <- repoLoadSkillCtx repo
            workerCtx  <- repoLoadWorkerCtx repo
            absenceCtx <- repoLoadAbsenceCtx repo
            cfg        <- repoLoadSchedulerConfig repo

            let ctx = SchedulerContext
                    { schSkillCtx    = skillCtx
                    , schWorkerCtx   = workerCtx
                    , schAbsenceCtx  = absenceCtx
                    , schSlots       = []
                    , schWorkers     = Set.empty
                    , schClosedSlots = Set.empty
                    , schShifts      = []
                    , schPrevWeekendWorkers = prevWeekendWorkers
                    , schConfig      = cfg
                    , schPeriodBounds = (diDateFrom draft, diDateTo draft)
                    , schCalendarHours = Map.empty
                    }

            -- Build combined schedule: look-back + draft assignments
            let combinedSched = Schedule (Set.union (unSchedule lookBackSched)
                                                    (unSchedule draftSched))

            -- Validate each draft assignment
            let violations = concatMap (\a ->
                    case validateAssignment ctx a combinedSched of
                        Just v  -> [v]
                        Nothing -> []
                    ) draftAssignments

            return (draftSched, violations)
