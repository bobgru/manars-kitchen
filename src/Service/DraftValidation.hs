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
      -- * The generalised core
    , validateSchedule
    ) where

import qualified Data.Set as Set
import Data.Time (Day, DayOfWeek(..), addDays, dayOfWeek)

import Domain.Types
    ( WorkerId
    , Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Schedule (bySlot)
import Domain.Scheduler (SchedulerContext(..), blockedByAlternateWeekend)
import Service.Context (loadValidationContext)
import Domain.Skill (qualified)
import Domain.Worker
    ( violatesRestPeriod, needsBreak
    , exceedsPermittedHours, wouldExceedDailyTotal
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
    -- Both hour rules use the *permissive* envelope, the one the scheduler
    -- applies when overtime is allowed. Using the strict rules here reported
    -- every legitimately-authorised overtime assignment as breaking a hard
    -- constraint: 'wouldBeOvertime' ignores the worker's overtime model and
    -- opt-in, and 'wouldExceedDailyRegular' is the 8-hour non-overtime
    -- threshold, not a ceiling.
    | exceedsPermittedHours (schWorkerCtx ctx) (schPeriodBounds ctx)
                            (schCalendarHours ctx) sched a =
        Just (DraftViolation a "period hours"
            "exceeds per-period hour limit, and overtime is not authorised")
    | wouldExceedDailyTotal (schConfig ctx) a sched =
        Just (DraftViolation a "daily hours" "would exceed maximum hours in one day")
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

-- | Which assignments in a schedule violate a hard constraint, judged against
-- the committed calendar around the range they occupy?
--
-- This is the generalised validation core. It takes a 'Schedule' and a range
-- rather than a draft, so the calendar can be fed through it as ADR 0004's
-- \"virtual default draft\" — there is deliberately no default draft /row/.
--
-- The look-back is the seven days of calendar before the range. It supplies the
-- previous-weekend workers the alternating-weekends rule needs, and it joins the
-- schedule under judgement so that rest-period and consecutive-hour rules can see
-- across the boundary. Note what it does /not/ do: it never looks at the calendar
-- /inside/ the range, which is the asymmetry 'calendarReplacedUnder' exists to
-- work around.
validateSchedule :: Repository -> (Day, Day) -> Schedule -> IO [DraftViolation]
validateSchedule repo (from, to) sched = do
    let assignments = Set.toList (unSchedule sched)
    if null assignments
        then return []
        else do
            lookBackSched <- Cal.loadCalendarSlice repo
                                 (addDays (-7) from) (addDays (-1) from)
            ctx <- loadValidationContext repo (from, to)
                       (buildLookBackContext lookBackSched)
            let combined = Schedule (Set.union (unSchedule lookBackSched)
                                               (unSchedule sched))
            return
                [ v
                | a <- assignments
                , Just v <- [validateAssignment ctx a combined]
                ]

-- | The shared body of 'computeDraftViolations' and 'pruneDraftViolations'.
-- Returns the draft's assignments alongside the violations so a caller that
-- prunes does not load them a second time.
validateDraft :: Repository -> DraftInfo -> IO (Schedule, [DraftViolation])
validateDraft repo draft = do
    draftSched <- repoLoadDraftAssignments repo (diId draft)
    violations <- validateSchedule repo (diDateFrom draft, diDateTo draft) draftSched
    return (draftSched, violations)
