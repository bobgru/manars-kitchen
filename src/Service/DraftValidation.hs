module Service.DraftValidation
    ( -- * Types
      DraftViolation(..)
      -- * Validation
    , validateAssignment
    , buildLookBackContext
    , validateDraftAgainstCalendar
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
import Repo.Types (Repository(..), DraftInfo(..))
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

-- | Validate a draft against the current calendar state.
-- Returns a list of violations (assignments that were removed).
validateDraftAgainstCalendar :: Repository -> Int -> IO [DraftViolation]
validateDraftAgainstCalendar repo draftId = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return []
        Just draft -> do
            -- Stale detection: check for calendar commits after last-validated timestamp
            commits <- repoCalendarCommitsAfter repo (diLastValidatedAt draft)
            if null commits
                then return []  -- not stale, skip validation
                else do
                    -- Load draft assignments
                    draftSched <- repoLoadDraftAssignments repo draftId
                    let draftAssignments = Set.toList (unSchedule draftSched)
                    if null draftAssignments
                        then do
                            -- No assignments to validate, just update timestamp
                            repoUpdateDraftValidatedAt repo draftId
                            return []
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

                            -- Auto-remove violating assignments
                            if null violations
                                then do
                                    repoUpdateDraftValidatedAt repo draftId
                                    return []
                                else do
                                    let violatingAssigns = Set.fromList (map dvAssignment violations)
                                        cleanedSched = Schedule (Set.difference
                                            (unSchedule draftSched) violatingAssigns)
                                    repoSaveDraftAssignments repo draftId cleanedSched
                                    repoUpdateDraftValidatedAt repo draftId
                                    return violations
