module Service.Draft
    ( -- * Draft lifecycle
      createDraft
    , generateDraft
    , commitDraft
    , discardDraft
    , listDrafts
    , loadDraft
      -- * Seeding
    , seedDraft
    , mergePinCalendar
      -- * Calendar hours
    , computeCalendarHours
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Time (Day, DiffTime)

import Domain.Types
    ( WorkerId, Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler
    ( SchedulerContext(..), ScheduleResult(..)
    , buildScheduleFrom, filterExemptCalendarHours
    )
import Domain.Worker (WorkerContext(..))
import Domain.Shift (defaultShifts)
import Domain.Skill (stationClosedSlots)
import Domain.Pin (expandPins)
import Domain.Calendar (generateDateRangeSlots, defaultHours)
import Domain.PayPeriod (defaultPayPeriodConfig, payPeriodBounds)
import Repo.Types (Repository(..), DraftInfo(..))
import qualified Service.Calendar as Cal

-- | Create a draft for a date range: check non-overlap, seed from
-- calendar + pins, save draft assignments, return draft_id.
createDraft :: Repository -> Day -> Day -> IO (Either String Int)
createDraft repo dateFrom dateTo = do
    overlap <- repoCheckDraftOverlap repo dateFrom dateTo
    if overlap
        then return (Left "Date range overlaps an existing draft.")
        else do
            draftId <- repoCreateDraft repo dateFrom dateTo
            seed <- seedDraft repo dateFrom dateTo
            repoSaveDraftAssignments repo draftId seed
            return (Right draftId)

-- | Seed a draft: load calendar slice, expand pins, merge with pin
-- precedence.
seedDraft :: Repository -> Day -> Day -> IO Schedule
seedDraft repo dateFrom dateTo = do
    calSched <- Cal.loadCalendarSlice repo dateFrom dateTo
    shifts <- repoLoadShifts repo
    pins <- repoLoadPins repo
    let activeShifts = case shifts of
            [] -> defaultShifts
            ss -> ss
        slots = generateDateRangeSlots defaultHours dateFrom dateTo Set.empty
        pinSched = expandPins activeShifts slots pins
    return (mergePinCalendar calSched pinSched)

-- | Merge calendar and pin schedules with pin precedence.
-- Conflict key: worker_id + slot_date + slot_start.
-- When a conflict exists, the pin assignment wins.
mergePinCalendar :: Schedule -> Schedule -> Schedule
mergePinCalendar (Schedule calAssigns) (Schedule pinAssigns) =
    let -- Build a map keyed by (worker_id, date, start_time) for calendar entries
        calMap = Map.fromList
            [ (conflictKey a, a) | a <- Set.toList calAssigns ]
        -- Build a map for pin entries (these override)
        pinMap = Map.fromList
            [ (conflictKey a, a) | a <- Set.toList pinAssigns ]
        -- Pins override calendar entries on the same conflict key
        merged = Map.union pinMap calMap
    in Schedule (Set.fromList (Map.elems merged))
  where
    conflictKey a =
        let s = assignSlot a
        in (assignWorker a, slotDate s, slotStart s)

-- | Pre-compute calendar hours per worker for a date range.
-- Loads calendar assignments and sums unique slot durations per worker,
-- filtering out exempt (per-diem) workers.
computeCalendarHours :: Repository -> WorkerContext -> Day -> Day
                     -> IO (Map.Map WorkerId DiffTime)
computeCalendarHours repo wctx periodStart periodEnd = do
    calSched <- Cal.loadCalendarSlice repo periodStart periodEnd
    let assignments = Set.toList (unSchedule calSched)
        -- Group by (worker, slot) to avoid counting multi-station duplicates
        uniqueSlots = Set.fromList [(assignWorker a, assignSlot a) | a <- assignments]
        -- Sum durations per worker
        raw = Set.foldl' (\acc (w, s) ->
            Map.insertWith (+) w (slotDuration s) acc)
            Map.empty uniqueSlots
    return (filterExemptCalendarHours wctx raw)

-- | Run the scheduler within a draft: load draft assignments as seed,
-- build slot list for date range, run buildScheduleFrom, save result.
generateDraft :: Repository -> Int -> Set.Set WorkerId -> IO (Either String ScheduleResult)
generateDraft repo draftId workers = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just draft -> do
            let dateFrom = diDateFrom draft
                dateTo   = diDateTo draft
            seed <- repoLoadDraftAssignments repo draftId
            let slots = generateDateRangeSlots defaultHours dateFrom dateTo Set.empty
            skillCtx   <- repoLoadSkillCtx repo
            workerCtx  <- repoLoadWorkerCtx repo
            absenceCtx <- repoLoadAbsenceCtx repo
            cfg        <- repoLoadSchedulerConfig repo
            shifts     <- repoLoadShifts repo
            -- Load pay period config to determine period bounds
            mPpc <- repoLoadPayPeriodConfig repo
            let ppc = maybe defaultPayPeriodConfig id mPpc
                periodBounds = payPeriodBounds ppc dateFrom
            -- Pre-compute calendar hours for the period
            calHrs <- computeCalendarHours repo workerCtx (fst periodBounds) (snd periodBounds)
            let closed = stationClosedSlots skillCtx slots
                ctx = SchedulerContext
                    { schSkillCtx    = skillCtx
                    , schWorkerCtx   = workerCtx
                    , schAbsenceCtx  = absenceCtx
                    , schSlots       = slots
                    , schWorkers     = workers
                    , schClosedSlots = closed
                    , schShifts      = shifts
                    , schPrevWeekendWorkers = Set.empty
                    , schConfig      = cfg
                    , schPeriodBounds = periodBounds
                    , schCalendarHours = calHrs
                    }
                result = buildScheduleFrom seed ctx
            repoSaveDraftAssignments repo draftId (srSchedule result)
            return (Right result)

-- | Commit a draft to the calendar: load draft assignments, call
-- commitToCalendar, delete draft.
commitDraft :: Repository -> Int -> Text -> IO (Either String ())
commitDraft repo draftId note = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just draft -> do
            sched <- repoLoadDraftAssignments repo draftId
            Cal.commitToCalendar repo (diDateFrom draft) (diDateTo draft) note sched
            repoDeleteDraft repo draftId
            return (Right ())

-- | Discard a draft: delete it and its assignments.
discardDraft :: Repository -> Int -> IO (Either String ())
discardDraft repo draftId = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just _ -> do
            repoDeleteDraft repo draftId
            return (Right ())

-- | List all active drafts.
listDrafts :: Repository -> IO [DraftInfo]
listDrafts = repoListDrafts

-- | Load draft metadata.
loadDraft :: Repository -> Int -> IO (Maybe DraftInfo)
loadDraft = repoGetDraft
