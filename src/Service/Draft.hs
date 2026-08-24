module Service.Draft
    ( -- * Draft lifecycle
      createDraft
    , generateDraft
    , commitDraft
    , discardDraft
    , listDrafts
    , loadDraft
      -- * Lifecycle inputs and outcomes
    , CreateDraftOpts(..)
    , defaultCreateDraftOpts
    , CreateDraftError(..)
    , FrozenRange(..)
    , CommitOutcome(..)
    , activeWorkerIds
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
    ( WorkerId, WorkerStatus(..), Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Scheduler
    ( SchedulerContext(..), ScheduleResult(..)
    , filterExemptCalendarHours
    )
import Service.Optimize (optimizeSchedule)
import Service.PubSub (TopicBus, ProgressEvent)
import Domain.Worker (WorkerContext(..))
import Domain.Shift (defaultShifts)
import Domain.Skill (stationClosedSlots)
import Domain.Pin (expandPins)
import Domain.Calendar (generateDateRangeSlots, defaultHours)
import Domain.PayPeriod (defaultPayPeriodConfig, payPeriodBounds)
import Repo.Types (Repository(..), DraftInfo(..))
import qualified Service.Calendar as Cal
import qualified Service.FreezeLine as Freeze

-- | What a caller brings to 'createDraft' beyond the date range.
--
-- Unfrozen ranges are session state — an @IORef@ in the CLI, and nothing at all
-- over REST — so they are passed in rather than looked up. A caller with neither
-- force nor unfreezes gets the strictest behaviour, which is what REST wants.
data CreateDraftOpts = CreateDraftOpts
    { cdoForce     :: !Bool
      -- ^ Create the draft even if the range covers frozen dates.
    , cdoUnfreezes :: !(Set.Set (Day, Day))
      -- ^ Ranges the caller has temporarily unfrozen.
    } deriving (Eq, Show)

-- | No force, no unfreezes: every frozen date is refused.
defaultCreateDraftOpts :: CreateDraftOpts
defaultCreateDraftOpts = CreateDraftOpts
    { cdoForce     = False
    , cdoUnfreezes = Set.empty
    }

-- | The frozen part of a requested date range, and the line that froze it.
-- Reported as first and last frozen date rather than every date, because that
-- is what both the CLI message and the REST body need.
data FrozenRange = FrozenRange
    { frFreezeLine :: !Day
    , frFrom       :: !Day
    , frTo         :: !Day
    } deriving (Eq, Show)

-- | Why 'createDraft' refused.
data CreateDraftError
    = DraftOverlapsExisting
    | DraftCoversFrozenDates !FrozenRange
    deriving (Eq, Show)

-- | What a caller needs to know after a successful 'commitDraft'.
data CommitOutcome = CommitOutcome
    { coCoveredFrozenDates :: !Bool
      -- ^ The committed range included dates on or before the freeze line, so a
      -- caller holding temporary unfreezes should clear them.
    } deriving (Eq, Show)

-- | Create a draft for a date range: refuse frozen dates unless forced, check
-- non-overlap, seed from calendar + pins, save draft assignments, return
-- draft_id.
--
-- The freeze check comes first so that a range which is both frozen and
-- overlapping reports the frozen dates — the more surprising of the two.
createDraft :: Repository -> CreateDraftOpts -> Day -> Day
            -> IO (Either CreateDraftError Int)
createDraft repo opts dateFrom dateTo = do
    freezeLine <- Freeze.computeFreezeLine
    let frozen = Freeze.frozenRangeFor freezeLine (cdoUnfreezes opts) dateFrom dateTo
    case frozen of
        Just (from, to) | not (cdoForce opts) ->
            return (Left (DraftCoversFrozenDates (FrozenRange freezeLine from to)))
        _ -> do
            overlap <- repoCheckDraftOverlap repo dateFrom dateTo
            if overlap
                then return (Left DraftOverlapsExisting)
                else do
                    draftId <- repoCreateDraft repo dateFrom dateTo
                    seed <- seedDraft repo dateFrom dateTo
                    repoSaveDraftAssignments repo draftId seed
                    return (Right draftId)

-- | The default candidate worker set: every user whose worker status is active.
-- Inactive workers and non-worker accounts are excluded, which is the point of
-- deactivating a worker.
activeWorkerIds :: Repository -> IO (Set.Set WorkerId)
activeWorkerIds repo = Set.fromList <$> repoLoadWorkerIdsByStatus repo WSActive

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
-- build slot list for date range, optimize, save result.
--
-- 'Nothing' for the candidate worker set means 'activeWorkerIds'. There is one
-- definition of that default so the CLI and REST cannot disagree about who is
-- available to schedule.
--
-- Optimization is gated on @opt-enabled@; when it is 0 (the default)
-- 'optimizeSchedule' is a single greedy build. Progress is published to the
-- supplied bus, which may have no subscribers.
generateDraft :: Repository -> Int -> Maybe (Set.Set WorkerId)
              -> TopicBus ProgressEvent
              -> IO (Either String ScheduleResult)
generateDraft repo draftId mWorkers progressBus = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just draft -> do
            let dateFrom = diDateFrom draft
                dateTo   = diDateTo draft
            workers <- maybe (activeWorkerIds repo) return mWorkers
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
            result <- optimizeSchedule ctx seed progressBus
            repoSaveDraftAssignments repo draftId (srSchedule result)
            return (Right result)

-- | Commit a draft to the calendar: load draft assignments, call
-- commitToCalendar, delete the draft and every what-if session saved against it.
--
-- The outcome reports whether the committed range reached back past the freeze
-- line. Clearing temporary unfreezes is the caller's job — they are session
-- state, and this function has no access to them — but deciding that they should
-- be cleared is not.
commitDraft :: Repository -> Int -> Text -> IO (Either String CommitOutcome)
commitDraft repo draftId note = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just draft -> do
            sched <- repoLoadDraftAssignments repo draftId
            Cal.commitToCalendar repo (diDateFrom draft) (diDateTo draft) note sched
            repoDeleteDraft repo draftId
            repoDeleteDraftHintSessions repo draftId
            freezeLine <- Freeze.computeFreezeLine
            let frozen = Freeze.frozenDatesInRange freezeLine
                            (diDateFrom draft) (diDateTo draft)
            return (Right (CommitOutcome { coCoveredFrozenDates = not (null frozen) }))

-- | Discard a draft: delete it, its assignments, and every what-if session
-- saved against it.
discardDraft :: Repository -> Int -> IO (Either String ())
discardDraft repo draftId = do
    mDraft <- repoGetDraft repo draftId
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just _ -> do
            repoDeleteDraft repo draftId
            repoDeleteDraftHintSessions repo draftId
            return (Right ())

-- | List all active drafts.
listDrafts :: Repository -> IO [DraftInfo]
listDrafts = repoListDrafts

-- | Load draft metadata.
loadDraft :: Repository -> Int -> IO (Maybe DraftInfo)
loadDraft = repoGetDraft
