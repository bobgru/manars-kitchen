module CLI.App
    ( AppState(..)
    , mkAppState
    , registerAuditSubscriber
    , registerTerminalEcho
    , runRepl
    , runDemo
    , handleCommand
    , isMutating
    ) where

import Control.Monad (forM_)
import System.IO (hFlush, stdout, hSetEcho, stdin)
import Control.Concurrent (threadDelay)
import Data.Char (toLower)
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import Data.Time
    ( Day, DayOfWeek(..), TimeOfDay(..), parseTimeM, defaultTimeLocale
    , addDays, fromGregorian, toGregorian, gregorianMonthLength, dayOfWeek
    )
import Data.Time.Clock (getCurrentTime, utctDay)

import Domain.Types
import qualified Domain.Shift
import Domain.Shift (ShiftDef(..))
import Domain.Skill (Skill(..), SkillContext(..), stationClosedSlots)
import qualified Domain.Scheduler as Scheduler
import qualified Domain.Diagnosis as Diagnosis
import qualified Domain.Calendar as Calendar
import Domain.Worker (WorkerContext(..), OvertimeModel(..), PayPeriodTracking(..))
import Domain.PayPeriod (PayPeriodConfig(..), parsePayPeriodType, showPayPeriodType,
                         payPeriodBounds, defaultPayPeriodConfig)
import Domain.Hint (Hint(..), Session(..), newSession, addHint, revertHint, revertTo, sessionStep)
import Domain.SchedulerConfig (presetNames, configToMap)
import Domain.Pin (expandPins, PinnedAssignment(..), PinSpec(..))
import Domain.Absence
    ( AbsenceType(..), AbsenceContext(..)
    )
import Auth.Types (User(..), UserId(..), Username(..), Role(..))
import Repo.Types (Repository(..), CalendarCommit(..), DraftInfo(..), AuditEntry(..), SessionId(..), HintSessionRecord(..))
import Service.HintRebase (ChangeCategory(..), RebaseResult(..), classifyChange, rebaseSession)
import qualified Audit.CommandMeta as Meta
import Service.Auth (AuthError(..), register, changePassword)
import qualified Service.Worker as SW
import qualified Service.Absence as SA
import qualified Service.Config as SC
import qualified Service.Optimize as Opt
import qualified Service.Calendar as Cal
import qualified Service.Draft as Draft
import Service.DraftValidation (DraftViolation(..), validateDraftAgainstCalendar)
import qualified Service.FreezeLine as Freeze
import qualified Export.JSON as Export
import Domain.Optimizer (OptProgress(..), OptPhase(..))
import Service.PubSub
    ( TopicBus, SubscriptionId, AppBus(..), newAppBus, newTopicBus
    , subscribe, unsubscribe
    , ProgressEvent(..), Source(..), CommandEvent(..)
    , publishCommand, sourceString
    )
import CLI.Commands (Command(..), parseCommand)
import CLI.Display
import CLI.Resolve
    ( EntityKind(..), EntityRef(..), SessionContext
    , emptyContext, resolveInput, lookupByName, entityKindName
    )
import Utils (shellQuote)

-- | Tracks hint session with persistence metadata.
data HintState = HintState
    { hstSess       :: !Session     -- ^ The live hint session
    , hstDraftId    :: !Int         -- ^ Draft this session is tied to
    , hstCheckpoint :: !Int         -- ^ Last-seen audit_log.id
    , hstIsStale    :: !Bool        -- ^ True if a mutation happened since last rebase
    } deriving (Show)

data AppState = AppState
    { asRepo       :: !Repository
    , asUser       :: !User
    , asSessionId  :: !SessionId
    , asBus        :: !AppBus
    , asContext    :: !(IORef SessionContext)
    , asCheckpoints :: !(IORef [String])
    , asUnfreezes  :: !(IORef (Set.Set (Day, Day)))
    , asHintSession :: !(IORef (Maybe HintState))
    }

-- | Create an AppState with initialized IORefs and event bus.
mkAppState :: Repository -> User -> SessionId -> IO AppState
mkAppState repo user sid = do
    bus    <- newAppBus
    ctxRef <- newIORef emptyContext
    cpRef  <- newIORef []
    ufRef  <- newIORef Set.empty
    hsRef  <- newIORef Nothing
    return (AppState repo user sid bus ctxRef cpRef ufRef hsRef)

registerAuditSubscriber :: TopicBus CommandEvent -> Repository -> IO SubscriptionId
registerAuditSubscriber cmdBus repo =
    subscribe cmdBus ".*" $ \_topic event ->
        repoLogCommandWithSource repo (T.pack $ ceUsername event) (T.pack $ ceCommand event) (T.pack $ sourceString (ceSource event))

registerTerminalEcho :: TopicBus CommandEvent -> IO SubscriptionId
registerTerminalEcho cmdBus =
    subscribe cmdBus ".*" $ \_topic event ->
        when (ceSource event /= CLI) $
            putStrLn ("[echo] " ++ ceCommand event)

runRepl :: AppState -> IO ()
runRepl st = do
    let Username uname = userName (asUser st)
        role = if userRole (asUser st) == Admin then "admin" else "user"
    putStr (T.unpack uname ++ " [" ++ role ++ "]> ")
    hFlush stdout
    line <- getLine
    -- Quick-parse for commands that don't need resolution
    case parseCommand line of
        Quit -> do
            repoCloseSession (asRepo st) (asSessionId st)
            putStrLn "Goodbye."
        Help -> printHelpSummary (userRole (asUser st)) >> runRepl st
        HelpGroup g -> printHelpGroup (userRole (asUser st)) g >> runRepl st
        CmdUse typ ref -> handleUse st typ ref >> runRepl st
        ContextView -> handleContextView st >> runRepl st
        ContextClear -> handleContextClear st >> runRepl st
        ContextClearType typ -> handleContextClearType st typ >> runRepl st
        CheckpointCreate mName -> handleCheckpointCreate st mName >> runRepl st
        CheckpointCommit -> handleCheckpointCommit st >> runRepl st
        CheckpointRollback mName -> handleCheckpointRollback st mName >> runRepl st
        CheckpointList -> handleCheckpointList st >> runRepl st
        _ -> do
            -- Resolve entity names and dot substitution
            resolved <- resolveInput (asRepo st) (asContext st) line
            case resolved of
                Left err -> putStrLn err >> runRepl st
                Right resolvedLine -> do
                    let cmd = parseCommand resolvedLine
                    when (isMutating cmd) $ do
                        publishCommand (busCommands (asBus st)) CLI (T.unpack uname) line
                        repoTouchSession (asRepo st) (asSessionId st)
                    handleCommand st cmd
                    -- Mark hint session as stale if a mutating command ran
                    when (isMutating cmd) $ do
                        mHs <- readIORef (asHintSession st)
                        case mHs of
                            Nothing -> return ()
                            Just hs -> do
                                cp <- getCurrentCheckpoint (asRepo st)
                                let hs' = hs { hstCheckpoint = cp, hstIsStale = True }
                                repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs)
                                    (sessHints (hstSess hs)) cp
                                writeIORef (asHintSession st) (Just hs')
                                putStrLn "Hint session is stale due to data change. Run 'what-if rebase' to reconcile, or continue adding hints (rebase will run automatically)."
                    runRepl st

-- | Commands that modify state and should be logged.
isMutating :: Command -> Bool
isMutating cmd = case cmd of
    ScheduleList        -> False
    ScheduleView _      -> False
    ScheduleViewCompact _ -> False
    ScheduleViewByWorker _  -> False
    ScheduleViewByStation _ -> False
    ScheduleHours _     -> False
    ScheduleDiagnose _  -> False
    SkillList           -> False
    SkillView _         -> False
    SkillInfo           -> False
    StationList         -> False
    WorkerInfo          -> False
    ShiftList           -> False
    AbsenceTypeList     -> False
    AbsenceListMine     -> False
    AbsenceListPending  -> False
    VacationRemaining _ -> False
    UserList            -> False
    Help                -> False
    HelpGroup _         -> False
    CmdUse _ _          -> False
    ContextView         -> False
    ContextClear        -> False
    ContextClearType _  -> False
    CheckpointCreate _  -> False
    CheckpointCommit    -> False
    CheckpointRollback _ -> False
    CheckpointList      -> False
    Quit                -> False
    Unknown _           -> False
    ConfigShow            -> False
    ConfigShowPayPeriod   -> False
    ConfigPresetList      -> False
    PinList               -> False
    DraftList             -> False
    DraftOpen _           -> False
    DraftView _           -> False
    DraftViewCompact _    -> False
    DraftHours _          -> False
    DraftDiagnose _       -> False
    CalendarView _ _         -> False
    CalendarViewByWorker _ _ -> False
    CalendarViewByStation _ _ -> False
    CalendarViewCompact _ _  -> False
    CalendarHours _ _        -> False
    CalendarDiagnose _ _     -> False
    CalendarHistory          -> False
    CalendarHistoryView _    -> False
    CalendarFreezeStatus     -> False
    WhatIfCloseStation {}  -> False
    WhatIfPin {}           -> False
    WhatIfAddWorker {}     -> False
    WhatIfWaiveOvertime _  -> False
    WhatIfGrantSkill _ _   -> False
    WhatIfOverridePrefs {} -> False
    WhatIfRevert           -> False
    WhatIfRevertAll        -> False
    WhatIfList             -> False
    WhatIfRebase           -> False
    -- WhatIfApply is mutating (persists changes)
    CmdExport _           -> False
    CmdExportSchedule _ _ -> False
    CmdAuditLog           -> False
    CmdReplay             -> False
    CmdReplayFile _       -> False
    CmdDemo               -> False
    _                     -> True

handleCommand :: AppState -> Command -> IO ()
handleCommand st cmd = case cmd of
    -- Schedule
    ScheduleList -> do
        names <- repoListSchedules (asRepo st)
        if null names
            then putStrLn "  (no schedules)"
            else mapM_ (\n -> putStrLn ("  " ++ T.unpack n)) names

    ScheduleView name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> do
                users <- repoListUsers (asRepo st)
                stations <- SW.listStations (asRepo st)
                skillCtx <- repoLoadSkillCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, T.unpack uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, T.unpack sname)
                        | (StationId sid, sname) <- stations ]
                putStr (displayScheduleTable workerNames stationNames
                           Calendar.defaultHours (scStationHours skillCtx) s)

    ScheduleViewCompact name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> do
                users <- repoListUsers (asRepo st)
                stations <- SW.listStations (asRepo st)
                skillCtx <- repoLoadSkillCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, T.unpack uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, T.unpack sname)
                        | (StationId sid, sname) <- stations ]
                putStr (displayScheduleCompact workerNames stationNames
                           Calendar.defaultHours (scStationHours skillCtx) s)

    ScheduleViewByWorker name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> putStr (displayScheduleByWorker s)

    ScheduleViewByStation name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> putStr (displayScheduleByStation s)

    ScheduleDelete name -> requireAdmin st $ do
        repoDeleteSchedule (asRepo st) (T.pack name)
        putStrLn ("Deleted schedule: " ++ name)

    ScheduleHours name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just sched -> do
                users <- repoListUsers (asRepo st)
                workerCtx <- repoLoadWorkerCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, T.unpack uname)
                        | u <- users, let Username uname = userName u ]
                putStr (displayWorkerHours workerNames
                           (wcMaxPeriodHours workerCtx)
                           sched)

    ScheduleDiagnose name -> do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just sched -> do
                users <- repoListUsers (asRepo st)
                stations <- SW.listStations (asRepo st)
                skills <- SW.listSkills (asRepo st)
                skillCtx   <- repoLoadSkillCtx (asRepo st)
                workerCtx  <- repoLoadWorkerCtx (asRepo st)
                absenceCtx <- repoLoadAbsenceCtx (asRepo st)
                shifts     <- repoLoadShifts (asRepo st)
                cfg        <- repoLoadSchedulerConfig (asRepo st)
                let workers = Set.fromList [userWorkerId u | u <- users]
                    -- Reconstruct the slots from the schedule's assignments
                    slots = Set.toList $ Set.map assignSlot (unSchedule sched)
                    closed = stationClosedSlots skillCtx slots
                    slotDates = map slotDate slots
                    periodBounds = case slotDates of
                        [] -> (toEnum 0, toEnum 0)
                        ds -> (minimum ds, addDays 1 (maximum ds))
                    ctx = Scheduler.SchedulerContext
                        { Scheduler.schSkillCtx    = skillCtx
                        , Scheduler.schWorkerCtx   = workerCtx
                        , Scheduler.schAbsenceCtx  = absenceCtx
                        , Scheduler.schSlots       = slots
                        , Scheduler.schWorkers     = workers
                        , Scheduler.schClosedSlots = closed
                        , Scheduler.schShifts      = shifts
                        , Scheduler.schPrevWeekendWorkers = Set.empty
                        , Scheduler.schConfig      = cfg
                        , Scheduler.schPeriodBounds = periodBounds
                        , Scheduler.schCalendarHours = Map.empty
                        }
                    result = Scheduler.buildScheduleFrom sched ctx
                    diags = Diagnosis.diagnose result ctx
                    workerNames = Map.fromList
                        [ (userWorkerId u, T.unpack uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, T.unpack sname)
                        | (StationId sid, sname) <- stations ]
                    skillNames = Map.fromList
                        [ (sid, T.unpack (skillName sk))
                        | (sid, sk) <- skills ]
                putStr (displayDiagnosis workerNames stationNames skillNames result diags)

    ScheduleClear name -> requireAdmin st $ do
        ms <- repoLoadSchedule (asRepo st) (T.pack name)
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just _  -> do
                repoSaveSchedule (asRepo st) (T.pack name) (Schedule Set.empty)
                putStrLn ("Cleared schedule: " ++ name)

    CmdAssign sched wid sid dateStr hr -> requireAdmin st $ do
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                ms <- repoLoadSchedule (asRepo st) (T.pack sched)
                case ms of
                    Nothing -> putStrLn "Schedule not found."
                    Just (Schedule as) -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            a = Assignment (WorkerId wid) (StationId sid) slot
                            sched' = Schedule (Set.insert a as)
                        repoSaveSchedule (asRepo st) (T.pack sched) sched'
                        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
                        putStrLn ("Assigned " ++ wname
                                 ++ " to Station " ++ show sid
                                 ++ " at " ++ dateStr ++ " " ++ show hr ++ ":00")

    CmdUnassign sched wid sid dateStr hr -> requireAdmin st $ do
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                ms <- repoLoadSchedule (asRepo st) (T.pack sched)
                case ms of
                    Nothing -> putStrLn "Schedule not found."
                    Just (Schedule as) -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            a = Assignment (WorkerId wid) (StationId sid) slot
                            sched' = Schedule (Set.delete a as)
                        repoSaveSchedule (asRepo st) (T.pack sched) sched'
                        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
                        putStrLn ("Unassigned " ++ wname
                                 ++ " from Station " ++ show sid
                                 ++ " at " ++ dateStr ++ " " ++ show hr ++ ":00")

    ScheduleCreate name dateStr -> requireAdmin st $ do
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                let slots = Calendar.generateWeekSlots Calendar.defaultHours day Set.empty
                if null slots
                    then putStrLn "No slots generated."
                    else do
                        users <- repoListUsers (asRepo st)
                        let workers = Set.fromList [userWorkerId u | u <- users]
                        putStrLn ("Generating schedule '" ++ name ++ "' for week of "
                                 ++ dateStr
                                 ++ " (" ++ show (length slots) ++ " slots, "
                                 ++ show (Set.size workers) ++ " workers)")
                        skillCtx   <- repoLoadSkillCtx (asRepo st)
                        workerCtx  <- repoLoadWorkerCtx (asRepo st)
                        absenceCtx <- repoLoadAbsenceCtx (asRepo st)
                        shifts     <- repoLoadShifts (asRepo st)
                        cfg        <- repoLoadSchedulerConfig (asRepo st)
                        pins       <- repoLoadPins (asRepo st)
                        let activeShifts = case shifts of
                                [] -> Domain.Shift.defaultShifts
                                ss -> ss
                            seed = expandPins activeShifts slots pins
                            closed = stationClosedSlots skillCtx slots
                            slotDates = map slotDate slots
                            periodBounds = case slotDates of
                                [] -> (toEnum 0, toEnum 0)
                                ds -> (minimum ds, addDays 1 (maximum ds))
                            ctx = Scheduler.SchedulerContext
                                { Scheduler.schSkillCtx    = skillCtx
                                , Scheduler.schWorkerCtx   = workerCtx
                                , Scheduler.schAbsenceCtx  = absenceCtx
                                , Scheduler.schSlots       = slots
                                , Scheduler.schWorkers     = workers
                                , Scheduler.schClosedSlots = closed
                                , Scheduler.schShifts      = shifts
                                , Scheduler.schPrevWeekendWorkers = Set.empty
                                , Scheduler.schConfig      = cfg
                                , Scheduler.schPeriodBounds = periodBounds
                                , Scheduler.schCalendarHours = Map.empty
                                }
                        progressBus <- newTopicBus
                        subId <- subscribe progressBus ".*" $ \_topic evt -> case evt of
                            OptimizeProgress progress ->
                                let phaseStr = case opPhase progress of
                                        PhaseHard -> "hard"
                                        PhaseSoft -> "soft"
                                    elapsed = showFFloat1 (opElapsedSecs progress)
                                in putStrLn ("[opt] phase=" ++ phaseStr
                                            ++ " iter=" ++ show (opIteration progress)
                                            ++ " unfilled=" ++ show (opBestUnfilled progress)
                                            ++ " score=" ++ showFFloat1 (opBestScore progress)
                                            ++ " elapsed=" ++ elapsed ++ "s")
                        result <- Opt.optimizeSchedule ctx seed progressBus
                        unsubscribe progressBus subId
                        let sched  = Scheduler.srSchedule result
                            unfilled = Scheduler.srUnfilled result
                            truly = length [u | u <- unfilled, Scheduler.unfilledKind u == Scheduler.TrulyUnfilled]
                            under = length unfilled - truly
                        repoSaveSchedule (asRepo st) (T.pack name) sched
                        putStrLn ("Saved. " ++ show (Set.size (unSchedule sched)) ++ " assignments, "
                                 ++ show truly ++ " unfilled, "
                                 ++ show under ++ " understaffed positions.")

    -- Draft
    DraftCreate startStr endStr force -> requireAdmin st $
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) ->
                createDraftWithFreezeCheck st s e force
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    DraftThisMonth -> requireAdmin st $ do
        today <- utctDay <$> getCurrentTime
        let (y, m, _) = toGregorian today
            lastDay = fromGregorian y m (gregorianMonthLength y m)
            dateFrom = addDays 1 today
        if dateFrom > lastDay
            then putStrLn "Error: no remaining days in the current month."
            else createDraftWithFreezeCheck st dateFrom lastDay False

    DraftNextMonth -> requireAdmin st $ do
        today <- utctDay <$> getCurrentTime
        let (y, m, _) = toGregorian today
            (ny, nm) = if m == 12 then (y + 1, 1) else (y, m + 1)
            dateFrom = fromGregorian ny nm 1
            dateTo   = fromGregorian ny nm (gregorianMonthLength ny nm)
        createDraftWithFreezeCheck st dateFrom dateTo False

    DraftList -> do
        drafts <- Draft.listDrafts (asRepo st)
        if null drafts
            then putStrLn "  (no active drafts)"
            else do
                putStrLn (padRight 6 "ID" ++ padRight 26 "Date Range"
                         ++ "Created At")
                putStrLn (replicate 60 '-')
                mapM_ (\d ->
                    let dateRange = show (diDateFrom d) ++ " to " ++ show (diDateTo d)
                    in putStrLn (padRight 6 (show (diId d))
                                ++ padRight 26 dateRange
                                ++ T.unpack (diCreatedAt d))
                    ) drafts

    DraftOpen didStr -> do
        let did = read didStr :: Int
        mDraft <- Draft.loadDraft (asRepo st) did
        case mDraft of
            Nothing -> putStrLn "Draft not found."
            Just d  -> do
                -- Validate draft against calendar before displaying
                violations <- validateDraftAgainstCalendar (asRepo st) did
                -- Display violation report if any
                if null violations
                    then return ()
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList [(s, T.unpack n) | (s, n) <- stations]
                        displayViolationReport d workerNames stationNames violations
                        putStrLn ""
                -- Load (possibly updated) draft assignments
                sched <- repoLoadDraftAssignments (asRepo st) did
                putStrLn ("Draft #" ++ show (diId d))
                putStrLn ("  Date range: " ++ show (diDateFrom d) ++ " to " ++ show (diDateTo d))
                putStrLn ("  Created at: " ++ T.unpack (diCreatedAt d))
                putStrLn ("  Assignments: " ++ show (Set.size (unSchedule sched)))
                -- Check for persisted hint session
                mPersistedHs <- repoLoadHintSession (asRepo st) (asSessionId st) did
                case mPersistedHs of
                    Nothing -> return ()
                    Just (HintSessionRecord hints cp) -> do
                        let n = length hints
                        putStr ("Found saved hint session (" ++ show n ++ " hints). Resume? [Y/n] ")
                        hFlush stdout
                        answer <- getLine
                        if map toLower answer `elem` ["", "y", "yes"]
                            then do
                                -- Rebuild session with persisted hints
                                rebuildResult <- buildSessionForDraft st did hints
                                case rebuildResult of
                                    Left err -> putStrLn ("Could not resume: " ++ err)
                                    Right sess -> do
                                        -- Check for stale entries
                                        entries <- repoAuditSince (asRepo st) cp
                                        let isStale = not (null entries)
                                        let hs = HintState sess did cp isStale
                                        writeIORef (asHintSession st) (Just hs)
                                        if isStale
                                            then do
                                                putStrLn ("Resumed hint session with " ++ show n ++ " hints.")
                                                putStrLn (show (length entries) ++ " changes since last save. Running rebase...")
                                                _ <- runRebase st hs
                                                return ()
                                            else putStrLn ("Resumed hint session with " ++ show n ++ " hints.")
                            else do
                                repoDeleteHintSession (asRepo st) (asSessionId st) did
                                putStrLn "Persisted hint session discarded."

    DraftView mDidStr -> do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                sched <- repoLoadDraftAssignments (asRepo st) did
                if Set.null (unSchedule sched)
                    then putStrLn "No assignments in this draft."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skillCtx <- repoLoadSkillCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                        putStr (displayScheduleTable workerNames stationNames
                                   Calendar.defaultHours (scStationHours skillCtx) sched)

    DraftViewCompact mDidStr -> do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                sched <- repoLoadDraftAssignments (asRepo st) did
                if Set.null (unSchedule sched)
                    then putStrLn "No assignments in this draft."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skillCtx <- repoLoadSkillCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                        putStr (displayScheduleCompact workerNames stationNames
                                   Calendar.defaultHours (scStationHours skillCtx) sched)

    DraftGenerate mDidStr -> requireAdmin st $ do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                users <- repoListUsers (asRepo st)
                let workers = Set.fromList [userWorkerId u | u <- users]
                result <- Draft.generateDraft (asRepo st) did workers
                case result of
                    Left err -> putStrLn ("Error: " ++ err)
                    Right sr -> do
                        let sched = Scheduler.srSchedule sr
                            unfilled = Scheduler.srUnfilled sr
                            truly = length [u | u <- unfilled, Scheduler.unfilledKind u == Scheduler.TrulyUnfilled]
                            under = length unfilled - truly
                        putStrLn ("Generated. " ++ show (Set.size (unSchedule sched)) ++ " assignments, "
                                 ++ show truly ++ " unfilled, "
                                 ++ show under ++ " understaffed positions.")

    DraftCommit mDidStr mNote -> requireAdmin st $ do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                -- Load draft metadata before commit (commit deletes the draft)
                mDraft <- Draft.loadDraft (asRepo st) did
                let note = T.pack (maybe "" id mNote)
                result <- Draft.commitDraft (asRepo st) did note
                case result of
                    Left err  -> putStrLn ("Error: " ++ err)
                    Right ()  -> do
                        putStrLn ("Draft #" ++ show did ++ " committed to calendar.")
                        -- Clean up hint session for this draft
                        repoDeleteHintSession (asRepo st) (asSessionId st) did
                        mHs <- readIORef (asHintSession st)
                        case mHs of
                            Just hs | hstDraftId hs == did -> writeIORef (asHintSession st) Nothing
                            _ -> return ()
                        -- Auto-refreeze: check if committed dates included historical dates
                        case mDraft of
                            Nothing -> return ()
                            Just draft -> do
                                freezeLine <- Freeze.computeFreezeLine
                                let frozen = Freeze.frozenDatesInRange freezeLine
                                                (diDateFrom draft) (diDateTo draft)
                                unfreezes <- readIORef (asUnfreezes st)
                                if not (null frozen) && not (Set.null unfreezes)
                                    then do
                                        writeIORef (asUnfreezes st) Set.empty
                                        putStrLn "Historical dates refrozen. All temporary unfreezes cleared."
                                    else return ()

    DraftDiscard mDidStr -> requireAdmin st $ do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                result <- Draft.discardDraft (asRepo st) did
                case result of
                    Left err  -> putStrLn ("Error: " ++ err)
                    Right ()  -> do
                        putStrLn ("Draft #" ++ show did ++ " discarded.")
                        -- Clean up hint session for this draft
                        repoDeleteHintSession (asRepo st) (asSessionId st) did
                        mHs <- readIORef (asHintSession st)
                        case mHs of
                            Just hs | hstDraftId hs == did -> writeIORef (asHintSession st) Nothing
                            _ -> return ()

    DraftHours mDidStr -> do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                sched <- repoLoadDraftAssignments (asRepo st) did
                if Set.null (unSchedule sched)
                    then putStrLn "No assignments in this draft."
                    else do
                        users <- repoListUsers (asRepo st)
                        workerCtx <- repoLoadWorkerCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                        putStr (displayWorkerHours workerNames
                                   (wcMaxPeriodHours workerCtx) sched)

    DraftDiagnose mDidStr -> do
        resolved <- resolveDraftId (asRepo st) mDidStr
        case resolved of
            Left err -> putStrLn err
            Right did -> do
                sched <- repoLoadDraftAssignments (asRepo st) did
                if Set.null (unSchedule sched)
                    then putStrLn "No assignments in this draft."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skills <- SW.listSkills (asRepo st)
                        skillCtx   <- repoLoadSkillCtx (asRepo st)
                        workerCtx  <- repoLoadWorkerCtx (asRepo st)
                        absenceCtx <- repoLoadAbsenceCtx (asRepo st)
                        shifts     <- repoLoadShifts (asRepo st)
                        cfg        <- repoLoadSchedulerConfig (asRepo st)
                        let workers = Set.fromList [userWorkerId u | u <- users]
                            slots = Set.toList $ Set.map assignSlot (unSchedule sched)
                            closed = stationClosedSlots skillCtx slots
                            slotDates = map slotDate slots
                            periodBounds = case slotDates of
                                [] -> (toEnum 0, toEnum 0)
                                ds -> (minimum ds, addDays 1 (maximum ds))
                            ctx = Scheduler.SchedulerContext
                                { Scheduler.schSkillCtx    = skillCtx
                                , Scheduler.schWorkerCtx   = workerCtx
                                , Scheduler.schAbsenceCtx  = absenceCtx
                                , Scheduler.schSlots       = slots
                                , Scheduler.schWorkers     = workers
                                , Scheduler.schClosedSlots = closed
                                , Scheduler.schShifts      = shifts
                                , Scheduler.schPrevWeekendWorkers = Set.empty
                                , Scheduler.schConfig      = cfg
                                , Scheduler.schPeriodBounds = periodBounds
                                , Scheduler.schCalendarHours = Map.empty
                                }
                            result = Scheduler.buildScheduleFrom sched ctx
                            diags = Diagnosis.diagnose result ctx
                            workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                            skillNames = Map.fromList
                                [ (sid, T.unpack (skillName sk))
                                | (sid, sk) <- skills ]
                        putStr (displayDiagnosis workerNames stationNames skillNames result diags)

    -- Calendar
    CalendarView startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skillCtx <- repoLoadSkillCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                        putStr (displayScheduleTable workerNames stationNames
                                   Calendar.defaultHours (scStationHours skillCtx) sched)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarViewByWorker startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else putStr (displayScheduleByWorker sched)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarViewByStation startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else putStr (displayScheduleByStation sched)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarViewCompact startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skillCtx <- repoLoadSkillCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                        putStr (displayScheduleCompact workerNames stationNames
                                   Calendar.defaultHours (scStationHours skillCtx) sched)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarHours startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else do
                        users <- repoListUsers (asRepo st)
                        workerCtx <- repoLoadWorkerCtx (asRepo st)
                        let workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                        putStr (displayWorkerHours workerNames
                                   (wcMaxPeriodHours workerCtx) sched)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarDiagnose startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                sched <- Cal.loadCalendarSlice (asRepo st) s e
                if Set.null (unSchedule sched)
                    then putStrLn "No calendar assignments in this range."
                    else do
                        users <- repoListUsers (asRepo st)
                        stations <- SW.listStations (asRepo st)
                        skills <- SW.listSkills (asRepo st)
                        skillCtx   <- repoLoadSkillCtx (asRepo st)
                        workerCtx  <- repoLoadWorkerCtx (asRepo st)
                        absenceCtx <- repoLoadAbsenceCtx (asRepo st)
                        shifts     <- repoLoadShifts (asRepo st)
                        cfg        <- repoLoadSchedulerConfig (asRepo st)
                        let workers = Set.fromList [userWorkerId u | u <- users]
                            slots = Set.toList $ Set.map assignSlot (unSchedule sched)
                            closed = stationClosedSlots skillCtx slots
                            slotDates = map slotDate slots
                            periodBounds = case slotDates of
                                [] -> (toEnum 0, toEnum 0)
                                ds -> (minimum ds, addDays 1 (maximum ds))
                            ctx = Scheduler.SchedulerContext
                                { Scheduler.schSkillCtx    = skillCtx
                                , Scheduler.schWorkerCtx   = workerCtx
                                , Scheduler.schAbsenceCtx  = absenceCtx
                                , Scheduler.schSlots       = slots
                                , Scheduler.schWorkers     = workers
                                , Scheduler.schClosedSlots = closed
                                , Scheduler.schShifts      = shifts
                                , Scheduler.schPrevWeekendWorkers = Set.empty
                                , Scheduler.schConfig      = cfg
                                , Scheduler.schPeriodBounds = periodBounds
                                , Scheduler.schCalendarHours = Map.empty
                                }
                            result = Scheduler.buildScheduleFrom sched ctx
                            diags = Diagnosis.diagnose result ctx
                            workerNames = Map.fromList
                                [ (userWorkerId u, T.unpack uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, T.unpack sname)
                                | (StationId sid, sname) <- stations ]
                            skillNames = Map.fromList
                                [ (sid, T.unpack (skillName sk))
                                | (sid, sk) <- skills ]
                        putStr (displayDiagnosis workerNames stationNames skillNames result diags)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarDoCommit name startStr endStr mNote -> requireAdmin st $
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                ms <- repoLoadSchedule (asRepo st) (T.pack name)
                case ms of
                    Nothing -> putStrLn ("Schedule not found: " ++ name)
                    Just sched -> do
                        let note = T.pack (maybe "" id mNote)
                        Cal.commitToCalendar (asRepo st) s e note sched
                        let n = Set.size (unSchedule sched)
                        putStrLn ("Committed " ++ show n ++ " assignments from '"
                                 ++ name ++ "' to calendar for "
                                 ++ startStr ++ " to " ++ endStr ++ ".")
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarHistory -> do
        commits <- Cal.listCalendarHistory (asRepo st)
        if null commits
            then putStrLn "  (no calendar history)"
            else do
                let idW = max 4 (maximum [length (show (ccId c)) | c <- commits]) + 1
                    dateW = 26
                putStrLn (padRight idW "ID" ++ padRight dateW "Date Range"
                         ++ padRight 22 "Committed At" ++ "Note")
                putStrLn (replicate (idW + dateW + 22 + 20) '-')
                mapM_ (\c ->
                    let dateRange = show (ccDateFrom c) ++ " to " ++ show (ccDateTo c)
                    in putStrLn (padRight idW (show (ccId c))
                                ++ padRight dateW dateRange
                                ++ padRight 22 (T.unpack (ccCommittedAt c))
                                ++ T.unpack (ccNote c))
                    ) commits

    CalendarHistoryView cidStr -> do
        let cid = read cidStr :: Int
        sched <- Cal.viewCommit (asRepo st) cid
        if Set.null (unSchedule sched)
            then do
                -- Check if the commit exists by listing all
                commits <- Cal.listCalendarHistory (asRepo st)
                if any (\c -> ccId c == cid) commits
                    then putStrLn ("Commit #" ++ show cid
                                  ++ " snapshot is empty (no assignments were replaced).")
                    else putStrLn ("Commit not found: " ++ show cid)
            else putStr (displayScheduleByStation sched)

    CalendarUnfreeze dateStr ->
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just d -> do
                freezeLine <- Freeze.computeFreezeLine
                if not (Freeze.isFrozen freezeLine d)
                    then putStrLn ("Date " ++ show d
                                  ++ " is not frozen (it is after the freeze line "
                                  ++ show freezeLine ++ ").")
                    else do
                        modifyIORef' (asUnfreezes st) (Set.insert (d, d))
                        putStrLn ("Unfrozen: " ++ show d
                                 ++ " (session only, will refreeze on commit or restart)")

    CalendarUnfreezeRange startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e)
                | s > e -> putStrLn "Invalid range: start date must be on or before end date."
                | otherwise -> do
                    freezeLine <- Freeze.computeFreezeLine
                    let frozenStart = s
                        frozenEnd   = min e freezeLine
                    if frozenStart > frozenEnd
                        then putStrLn ("No dates in range are frozen (all after freeze line "
                                      ++ show freezeLine ++ ").")
                        else do
                            modifyIORef' (asUnfreezes st) (Set.insert (frozenStart, frozenEnd))
                            if e > freezeLine
                                then putStrLn ("Unfrozen: " ++ show frozenStart ++ " to "
                                              ++ show frozenEnd
                                              ++ " (session only, dates after freeze line already unfrozen)")
                                else putStrLn ("Unfrozen: " ++ show frozenStart ++ " to "
                                              ++ show frozenEnd ++ " (session only)")
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarFreezeStatus -> do
        freezeLine <- Freeze.computeFreezeLine
        putStrLn ("Freeze line: " ++ show freezeLine ++ " (yesterday)")
        unfreezes <- readIORef (asUnfreezes st)
        if Set.null unfreezes
            then putStrLn "No temporary unfreezes active."
            else do
                let ranges = Set.toAscList unfreezes
                mapM_ (\(s, e) ->
                    if s == e
                        then putStrLn ("Unfrozen ranges: " ++ show s)
                        else putStrLn ("Unfrozen ranges: " ++ show s ++ " to " ++ show e)
                    ) ranges

    -- What-if (hint session)
    WhatIfCloseStation sid dateStr hr -> requireAdmin st $ requireDraft st $
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                result <- getOrInitSession st
                case result of
                    Left err -> putStrLn err
                    Right hs -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            hint = CloseStation (StationId sid) slot
                            sess = hstSess hs
                            oldResult = sessResult sess
                            sess' = addHint hint sess
                            hs' = hs { hstSess = sess' }
                        autoSaveHintSession st hs'
                        (wNames, sNames, _) <- loadNameMaps st
                        putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))

    WhatIfPin wid sid dateStr hr -> requireAdmin st $ requireDraft st $
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                result <- getOrInitSession st
                case result of
                    Left err -> putStrLn err
                    Right hs -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            hint = PinAssignment (WorkerId wid) (StationId sid) slot
                            sess = hstSess hs
                            oldResult = sessResult sess
                            sess' = addHint hint sess
                            hs' = hs { hstSess = sess' }
                        autoSaveHintSession st hs'
                        (wNames, sNames, _) <- loadNameMaps st
                        putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))

    WhatIfAddWorker name skillStrs mHours -> requireAdmin st $ requireDraft st $ do
        -- Resolve skill names to SkillIds
        resolvedSkills <- mapM (lookupByName (asRepo st) ESkill) skillStrs
        case sequence resolvedSkills of
            Left err -> putStrLn err
            Right sidStrs -> do
                result <- getOrInitSession st
                case result of
                    Left err -> putStrLn err
                    Right hs -> do
                        let sess = hstSess hs
                            sids = Set.fromList [SkillId (read s) | s <- sidStrs]
                            tempWid = WorkerId (9000 + sessionStep sess)
                            diffHours = fmap (\h -> fromIntegral (h * 3600)) mHours
                            hint = AddWorker tempWid sids diffHours
                            oldResult = sessResult sess
                            sess' = addHint hint sess
                            hs' = hs { hstSess = sess' }
                        autoSaveHintSession st hs'
                        (wNames, sNames, _) <- loadNameMaps st
                        let wNames' = Map.insert tempWid name wNames
                        putStr (displayHintDiff wNames' sNames oldResult (sessResult sess'))

    WhatIfWaiveOvertime wid -> requireAdmin st $ requireDraft st $ do
        result <- getOrInitSession st
        case result of
            Left err -> putStrLn err
            Right hs -> do
                let hint = WaiveOvertime (WorkerId wid)
                    sess = hstSess hs
                    oldResult = sessResult sess
                    sess' = addHint hint sess
                    hs' = hs { hstSess = sess' }
                autoSaveHintSession st hs'
                (wNames, sNames, _) <- loadNameMaps st
                putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))

    WhatIfGrantSkill wid sid -> requireAdmin st $ requireDraft st $ do
        result <- getOrInitSession st
        case result of
            Left err -> putStrLn err
            Right hs -> do
                let hint = GrantSkill (WorkerId wid) sid
                    sess = hstSess hs
                    oldResult = sessResult sess
                    sess' = addHint hint sess
                    hs' = hs { hstSess = sess' }
                autoSaveHintSession st hs'
                (wNames, sNames, _) <- loadNameMaps st
                putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))

    WhatIfOverridePrefs wid sids -> requireAdmin st $ requireDraft st $ do
        result <- getOrInitSession st
        case result of
            Left err -> putStrLn err
            Right hs -> do
                let hint = OverridePreference (WorkerId wid) (map StationId sids)
                    sess = hstSess hs
                    oldResult = sessResult sess
                    sess' = addHint hint sess
                    hs' = hs { hstSess = sess' }
                autoSaveHintSession st hs'
                (wNames, sNames, _) <- loadNameMaps st
                putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))

    WhatIfRevert -> requireDraft st $ do
        mHs <- readIORef (asHintSession st)
        case mHs of
            Nothing -> putStrLn "No hints to revert."
            Just hs | null (sessHints (hstSess hs)) -> putStrLn "No hints to revert."
            Just hs -> do
                let sess = hstSess hs
                    n = sessionStep sess
                    oldResult = sessResult sess
                    sess' = revertHint sess
                    hs' = hs { hstSess = sess' }
                autoSaveHintSession st hs'
                (wNames, sNames, _) <- loadNameMaps st
                putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))
                putStrLn ("Reverted hint " ++ show n ++ ". "
                         ++ show (sessionStep sess') ++ " hint"
                         ++ (if sessionStep sess' == 1 then "" else "s")
                         ++ " remaining.")

    WhatIfRevertAll -> requireDraft st $ do
        mHs <- readIORef (asHintSession st)
        case mHs of
            Nothing -> putStrLn "No hints to revert."
            Just hs | null (sessHints (hstSess hs)) -> putStrLn "No hints to revert."
            Just hs -> do
                let sess = hstSess hs
                    n = sessionStep sess
                    oldResult = sessResult sess
                    sess' = revertTo 0 sess
                    hs' = hs { hstSess = sess' }
                autoSaveHintSession st hs'
                (wNames, sNames, _) <- loadNameMaps st
                putStr (displayHintDiff wNames sNames oldResult (sessResult sess'))
                putStrLn ("Reverted all " ++ show n ++ " hints.")

    WhatIfList -> requireDraft st $ do
        mHs <- readIORef (asHintSession st)
        case mHs of
            Nothing -> putStrLn "No active hints."
            Just hs -> do
                (wNames, sNames, skNames) <- loadNameMaps st
                putStr (displayHintList wNames sNames skNames (hstSess hs))

    WhatIfApply -> requireAdmin st $ requireDraft st $ do
        mHs <- readIORef (asHintSession st)
        case mHs of
            Nothing -> putStrLn "No hints to apply."
            Just hs | null (sessHints (hstSess hs)) -> putStrLn "No hints to apply."
            Just hs -> do
                let sess = hstSess hs
                    lastHint = last (sessHints sess)
                (wNames, sNames, skNames) <- loadNameMaps st
                case lastHint of
                    GrantSkill (WorkerId w) (SkillId sk) -> do
                        SW.grantWorkerSkill (asRepo st) (WorkerId w) (SkillId sk)
                        putStrLn ("Applied: grant skill "
                                 ++ Map.findWithDefault ("Skill " ++ show sk) (SkillId sk) skNames
                                 ++ " to " ++ lookupWorker wNames (WorkerId w))
                        rebuildSessionAfterApply st hs
                    WaiveOvertime (WorkerId w) -> do
                        _ <- SW.setOvertimeOptIn (asRepo st) (WorkerId w) True
                        putStrLn ("Applied: waive overtime for "
                                 ++ lookupWorker wNames (WorkerId w))
                        rebuildSessionAfterApply st hs
                    OverridePreference (WorkerId w) sids -> do
                        SW.setStationPreferences (asRepo st) (WorkerId w) sids
                        putStrLn ("Applied: override preferences for "
                                 ++ lookupWorker wNames (WorkerId w))
                        rebuildSessionAfterApply st hs
                    PinAssignment (WorkerId w) (StationId s) slot -> do
                        let day = slotDate slot
                            dow = dayOfWeek day
                            hr  = let TimeOfDay h _ _ = slotStart slot in h
                        SW.addPin (asRepo st) (PinnedAssignment (WorkerId w) (StationId s) dow (PinSlot hr))
                        putStrLn ("Applied: pin " ++ lookupWorker wNames (WorkerId w)
                                 ++ " at " ++ lookupStation sNames (StationId s)
                                 ++ " on " ++ showDayOfWeek dow ++ " " ++ show hr ++ ":00")
                        rebuildSessionAfterApply st hs
                    AddWorker {} ->
                        putStrLn "Cannot apply AddWorker hints automatically. Create the worker manually with 'user create' and 'worker grant-skill', then regenerate the schedule."
                    CloseStation {} ->
                        putStrLn "Cannot apply CloseStation hints automatically. Use 'station close-day' for day-level closures, or adjust station hours with 'station set-hours'."

    WhatIfRebase -> requireDraft st $ do
        mHs <- readIORef (asHintSession st)
        case mHs of
            Nothing -> putStrLn "No active hint session to rebase."
            Just hs -> do
                _ <- runRebase st hs
                return ()

    -- Stations (admin)
    StationAdd name -> requireAdmin st $ do
        _sid <- SW.addStation (asRepo st) (T.pack name)
        putStrLn ("Added station: " ++ name)

    StationList -> do
        stations <- SW.listStations (asRepo st)
        if null stations
            then putStrLn "  (no stations)"
            else mapM_ (\(_sid, name) ->
                putStrLn ("  " ++ T.unpack name)
                ) stations

    StationRemove sid -> requireAdmin st $ do
        SW.removeStation (asRepo st) (StationId sid)
        putStrLn ("Removed station " ++ show sid)

    StationSetHours sid sh eh -> requireAdmin st $ do
        SW.setStationHours (asRepo st) (StationId sid) sh eh
        putStrLn ("Set station hours: " ++ show sh ++ ":00-" ++ show eh ++ ":00")

    StationSetMultiHours sid sh eh -> requireAdmin st $ do
        SW.setMultiStationHours (asRepo st) (StationId sid) sh eh
        putStrLn ("Set station multi-station hours: " ++ show sh ++ ":00-" ++ show eh ++ ":00")

    StationCloseDay sid dayStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                SW.closeStationDay (asRepo st) (StationId sid) dow
                putStrLn ("Station closed on " ++ dayStr)

    StationRequireSkill sid skid -> requireAdmin st $ do
        ctx <- repoLoadSkillCtx (asRepo st)
        let current = Map.findWithDefault Set.empty (StationId sid) (scStationRequires ctx)
        SW.setStationRequiredSkills (asRepo st) (StationId sid) (Set.insert skid current)
        sname <- lookupSkillName (asRepo st) skid
        putStrLn ("Station now requires skill " ++ sname)

    StationRemoveRequiredSkill sid skid -> requireAdmin st $ do
        ctx <- repoLoadSkillCtx (asRepo st)
        let current = Map.findWithDefault Set.empty (StationId sid) (scStationRequires ctx)
        SW.setStationRequiredSkills (asRepo st) (StationId sid) (Set.delete skid current)
        sname <- lookupSkillName (asRepo st) skid
        putStrLn ("Station no longer requires skill " ++ sname)

    SkillCreate name -> requireAdmin st $ do
        result <- SW.addSkill (asRepo st) (T.pack name) T.empty
        case result of
            Left err -> putStrLn $ "Error: " ++ err
            Right () -> putStrLn $ "Created " ++ shellQuote name

    SkillRename sid name -> requireAdmin st $ do
        oldName <- lookupSkillName (asRepo st) sid
        repoRenameSkill (asRepo st) sid (T.pack name)
        putStrLn ("Renamed " ++ oldName ++ " to \"" ++ name ++ "\"")

    SkillDelete sid -> requireAdmin st $ do
        sname <- lookupSkillName (asRepo st) sid
        result <- SW.safeDeleteSkill (asRepo st) sid
        case result of
            Right () -> putStrLn ("Deleted " ++ sname)
            Left refs -> do
                putStrLn ("Error: " ++ sname ++ " is still referenced:")
                displaySkillRefs refs

    SkillForceDelete sid -> requireAdmin st $ do
        refs <- SW.checkSkillReferences (asRepo st) sid
        if SW.isUnreferenced refs
            then handleCommand st (SkillDelete sid)
            else do
                forM_ (SW.srWorkers refs) $ \(wid, _) ->
                    handleCommand st (WorkerRevokeSkill (let WorkerId w = wid in w) sid)
                forM_ (SW.srStations refs) $ \(stid, _) ->
                    handleCommand st (StationRemoveRequiredSkill (let StationId s = stid in s) sid)
                forM_ (SW.srCrossTraining refs) $ \(wid, _) ->
                    handleCommand st (WorkerClearCrossTraining (let WorkerId w = wid in w) sid)
                forM_ (SW.srImpliedBy refs) $ \(implier, _) ->
                    handleCommand st (SkillRemoveImplication implier sid)
                forM_ (SW.srImplies refs) $ \(implied, _) ->
                    handleCommand st (SkillRemoveImplication sid implied)
                handleCommand st (SkillDelete sid)

    SkillList -> do
        skills <- SW.listSkills (asRepo st)
        if null skills
            then putStrLn "  (no skills)"
            else mapM_ (\(_sid, sk) ->
                putStrLn ("  " ++ T.unpack (skillName sk))
                ) skills

    SkillImplication a b -> requireAdmin st $ do
        SW.addSkillImplication (asRepo st) a b
        aname <- lookupSkillName (asRepo st) a
        bname <- lookupSkillName (asRepo st) b
        putStrLn (aname ++ " now implies " ++ bname)

    SkillRemoveImplication a b -> requireAdmin st $ do
        SW.removeSkillImplication (asRepo st) a b
        aname <- lookupSkillName (asRepo st) a
        bname <- lookupSkillName (asRepo st) b
        putStrLn ("Removed: " ++ aname ++ " no longer implies " ++ bname)

    SkillView sid -> do
        skills <- repoListSkills (asRepo st)
        case lookup sid skills of
            Nothing -> do
                sname <- lookupSkillName (asRepo st) sid
                putStrLn ("Unknown skill: " ++ sname)
            Just sk -> do
                ctx <- repoLoadSkillCtx (asRepo st)
                wctx <- repoLoadWorkerCtx (asRepo st)
                users <- repoListUsers (asRepo st)
                stations <- repoListStations (asRepo st)
                let workerNames = Map.fromList [(userWorkerId u, let Username n = userName u in T.unpack n) | u <- users]
                    stationNames = Map.fromList [(s, T.unpack n) | (s, n) <- stations]
                    skillNames = Map.fromList [(s, skillName sk') | (s, sk') <- skills]
                putStr (displaySkillView sid sk ctx wctx workerNames stationNames skillNames)

    SkillInfo -> do
        ctx <- repoLoadSkillCtx (asRepo st)
        putStr (displaySkillCtx ctx)

    -- Worker skills (admin)
    WorkerGrantSkill wid sid -> requireAdmin st $ do
        SW.grantWorkerSkill (asRepo st) (WorkerId wid) sid
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        sname <- lookupSkillName (asRepo st) sid
        putStrLn ("Granted " ++ sname ++ " to " ++ wname)

    WorkerRevokeSkill wid sid -> requireAdmin st $ do
        SW.revokeWorkerSkill (asRepo st) (WorkerId wid) sid
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        sname <- lookupSkillName (asRepo st) sid
        putStrLn ("Revoked " ++ sname ++ " from " ++ wname)

    -- Worker context (admin)
    WorkerSetHours wid h -> requireAdmin st $ do
        SW.setMaxHours (asRepo st) (WorkerId wid) (fromIntegral (h * 3600))
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn ("Set " ++ wname ++ " max hours: " ++ show h ++ "h/period")

    WorkerSetOvertime wid b -> requireAdmin st $ do
        mWarn <- SW.setOvertimeOptIn (asRepo st) (WorkerId wid) b
        case mWarn of
            Just warning -> putStrLn warning
            Nothing -> do
                wname <- lookupWorkerName (asRepo st) (WorkerId wid)
                putStrLn (wname ++ " overtime: " ++ if b then "on" else "off")

    WorkerSetPrefs wid sids -> requireAdmin st $ do
        SW.setStationPreferences (asRepo st) (WorkerId wid) (map StationId sids)
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn ("Set " ++ wname ++ " preferences")

    WorkerSetVariety wid b -> requireAdmin st $ do
        SW.setVarietyPreference (asRepo st) (WorkerId wid) b
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ " variety: " ++ if b then "on" else "off")

    WorkerSetShiftPref wid names -> requireAdmin st $ do
        SW.setShiftPreferences (asRepo st) (WorkerId wid) (map T.pack names)
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn ("Set " ++ wname ++ " shift prefs: " ++ unwords names)

    WorkerSetWeekendOnly wid b -> requireAdmin st $ do
        SW.setWeekendOnly (asRepo st) (WorkerId wid) b
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ " weekend-only: " ++ if b then "on" else "off")

    WorkerInfo -> do
        ctx <- repoLoadWorkerCtx (asRepo st)
        putStr (displayWorkerCtx ctx)

    WorkerSetSeniority wid lvl -> requireAdmin st $ do
        SW.setSeniority (asRepo st) (WorkerId wid) lvl
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn ("Set " ++ wname ++ " seniority level: " ++ show lvl)

    WorkerSetCrossTraining wid sid -> requireAdmin st $ do
        SW.addCrossTraining (asRepo st) (WorkerId wid) sid
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        sname <- lookupSkillName (asRepo st) sid
        putStrLn ("Added cross-training goal: " ++ wname ++ " -> " ++ sname)

    WorkerClearCrossTraining wid sid -> requireAdmin st $ do
        SW.removeCrossTraining (asRepo st) (WorkerId wid) sid
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        sname <- lookupSkillName (asRepo st) sid
        putStrLn ("Removed cross-training goal: " ++ wname ++ " -> " ++ sname)

    WorkerAvoidPairing w1 w2 -> requireAdmin st $ do
        SW.addAvoidPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        n1 <- lookupWorkerName (asRepo st) (WorkerId w1)
        n2 <- lookupWorkerName (asRepo st) (WorkerId w2)
        putStrLn (n1 ++ " and " ++ n2 ++ " will avoid concurrent assignment")

    WorkerClearAvoidPairing w1 w2 -> requireAdmin st $ do
        SW.removeAvoidPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        n1 <- lookupWorkerName (asRepo st) (WorkerId w1)
        n2 <- lookupWorkerName (asRepo st) (WorkerId w2)
        putStrLn ("Cleared avoid-pairing: " ++ n1 ++ " and " ++ n2)

    WorkerPreferPairing w1 w2 -> requireAdmin st $ do
        SW.addPreferPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        n1 <- lookupWorkerName (asRepo st) (WorkerId w1)
        n2 <- lookupWorkerName (asRepo st) (WorkerId w2)
        putStrLn (n1 ++ " and " ++ n2 ++ " prefer concurrent assignment")

    WorkerClearPreferPairing w1 w2 -> requireAdmin st $ do
        SW.removePreferPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        n1 <- lookupWorkerName (asRepo st) (WorkerId w1)
        n2 <- lookupWorkerName (asRepo st) (WorkerId w2)
        putStrLn ("Cleared prefer-pairing: " ++ n1 ++ " and " ++ n2)

    -- Employment status
    WorkerSetStatus wid status -> requireAdmin st $ do
        msg <- SW.setEmploymentStatus (asRepo st) (WorkerId wid) status
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ ": " ++ msg)

    WorkerSetOvertimeModel wid model -> requireAdmin st $ do
        case model of
            "eligible"    -> SW.setOvertimeModel (asRepo st) (WorkerId wid) OTEligible
            "manual-only" -> SW.setOvertimeModel (asRepo st) (WorkerId wid) OTManualOnly
            "exempt"      -> SW.setOvertimeModel (asRepo st) (WorkerId wid) OTExempt
            _ -> do putStrLn ("Unknown overtime model: " ++ model ++ ". Use eligible|manual-only|exempt.")
                    return ()
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ " overtime model: " ++ model)

    WorkerSetPayTracking wid tracking -> requireAdmin st $ do
        case tracking of
            "standard" -> SW.setPayPeriodTracking (asRepo st) (WorkerId wid) PPStandard
            "exempt"   -> SW.setPayPeriodTracking (asRepo st) (WorkerId wid) PPExempt
            _ -> do putStrLn ("Unknown pay tracking: " ++ tracking ++ ". Use standard|exempt.")
                    return ()
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ " pay tracking: " ++ tracking)

    WorkerSetTemp wid b -> requireAdmin st $ do
        SW.setTempFlag (asRepo st) (WorkerId wid) b
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        putStrLn (wname ++ " temp: " ++ if b then "on" else "off")

    -- Pinned assignments
    PinAdd wid sid dayStr specStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                let spec = if all (`elem` "0123456789") specStr
                           then PinSlot (read specStr)
                           else PinShift (T.pack specStr)
                    pin = PinnedAssignment (WorkerId wid) (StationId sid) dow spec
                SW.addPin (asRepo st) pin
                wname <- lookupWorkerName (asRepo st) (WorkerId wid)
                putStrLn ("Pinned " ++ wname ++ " at Station " ++ show sid
                         ++ " on " ++ dayStr ++ " " ++ specStr)

    PinRemove wid sid dayStr specStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                let spec = if all (`elem` "0123456789") specStr
                           then PinSlot (read specStr)
                           else PinShift (T.pack specStr)
                    pin = PinnedAssignment (WorkerId wid) (StationId sid) dow spec
                SW.removePin (asRepo st) pin
                wname <- lookupWorkerName (asRepo st) (WorkerId wid)
                putStrLn ("Unpinned " ++ wname ++ " at Station " ++ show sid
                         ++ " on " ++ dayStr ++ " " ++ specStr)

    PinList -> do
        pins <- SW.listPins (asRepo st)
        if null pins
            then putStrLn "  (no pinned assignments)"
            else mapM_ (\p -> do
                wname <- lookupWorkerName (asRepo st) (pinWorker p)
                putStrLn ("  " ++ wname
                         ++ " @ Station " ++ show (let StationId s = pinStation p in s)
                         ++ " on " ++ showDayOfWeek (pinDay p)
                         ++ " " ++ showPinSpec (pinSpec p))
                ) pins

    -- Config
    ConfigShow -> do
        params <- SC.listConfigParams (asRepo st)
        putStr (displayConfig params)

    ConfigSet key val -> requireAdmin st $
        case reads val :: [(Double, String)] of
            [(v, "")] -> do
                result <- SC.setConfigParam (asRepo st) key v
                case result of
                    Nothing -> putStrLn ("Unknown config key: " ++ key)
                    Just _  -> putStrLn ("Set " ++ key ++ " = " ++ val)
            _ -> putStrLn ("Invalid value: " ++ val ++ " (expected a number)")

    ConfigPreset name -> requireAdmin st $ do
        result <- SC.applyPreset (asRepo st) name
        case result of
            Nothing  -> putStrLn ("Unknown preset: " ++ name
                                  ++ ". Available: " ++ unwords presetNames)
            Just cfg -> do
                putStrLn ("Applied preset: " ++ name)
                putStr (displayConfig (Map.toList (configToMap cfg)))

    ConfigPresetList -> do
        putStrLn "Available presets:"
        mapM_ (\n -> putStrLn ("  " ++ n)) presetNames

    ConfigReset -> requireAdmin st $ do
        _ <- SC.applyPreset (asRepo st) "balanced"
        putStrLn "Config reset to defaults (balanced preset)."

    ConfigSetPayPeriod typ anchor -> requireAdmin st $
        case parsePayPeriodType typ of
            Nothing -> putStrLn ("Unknown pay period type: " ++ typ
                                 ++ ". Valid types: weekly, biweekly, semi-monthly, monthly")
            Just ppType -> case parseDay anchor of
                Nothing -> putStrLn ("Invalid date format: " ++ anchor ++ " (expected YYYY-MM-DD)")
                Just anchorDay -> do
                    let ppc = PayPeriodConfig ppType anchorDay
                    SC.savePayPeriodConfig (asRepo st) ppc
                    let (s, e) = payPeriodBounds ppc anchorDay
                    putStrLn ("Pay period set: " ++ showPayPeriodType ppType
                             ++ ", anchor " ++ anchor)
                    putStrLn ("Current period: " ++ show s ++ " to " ++ show e)

    ConfigShowPayPeriod -> do
        mPpc <- SC.loadPayPeriodConfig (asRepo st)
        case mPpc of
            Nothing -> do
                let def = defaultPayPeriodConfig
                putStrLn ("Pay period: " ++ showPayPeriodType (ppcType def)
                         ++ " (default)")
                putStrLn ("Anchor date: " ++ show (ppcAnchorDate def))
            Just ppc -> do
                today <- utctDay <$> getCurrentTime
                let (s, e) = payPeriodBounds ppc today
                putStrLn ("Pay period: " ++ showPayPeriodType (ppcType ppc))
                putStrLn ("Anchor date: " ++ show (ppcAnchorDate ppc))
                putStrLn ("Current period: " ++ show s ++ " to " ++ show e)

    -- Shifts (admin)
    ShiftCreate name sh eh -> requireAdmin st $ do
        repoSaveShift (asRepo st) (ShiftDef (T.pack name) sh eh)
        putStrLn ("Created shift: " ++ name ++ " (" ++ show sh ++ ":00-" ++ show eh ++ ":00)")

    ShiftList -> do
        shifts <- repoLoadShifts (asRepo st)
        if null shifts
            then putStrLn "  (no shifts configured — using defaults)"
            else mapM_ (\sd ->
                putStrLn ("  " ++ T.unpack (sdName sd) ++ ": "
                         ++ show (sdStart sd) ++ ":00-" ++ show (sdEnd sd) ++ ":00")
                ) shifts

    ShiftDelete name -> requireAdmin st $ do
        repoDeleteShift (asRepo st) (T.pack name)
        putStrLn ("Deleted shift: " ++ name)

    -- Absence types (admin)
    AbsenceTypeCreate name lim -> requireAdmin st $ do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        let nextTid = if Map.null (acTypes ctx)
                      then 1
                      else let AbsenceTypeId maxId = maximum (Map.keys (acTypes ctx))
                           in maxId + 1
            at = AbsenceType { atName = T.pack name, atYearlyLimit = lim }
            ctx' = ctx { acTypes = Map.insert (AbsenceTypeId nextTid) at (acTypes ctx) }
        repoSaveAbsenceCtx (asRepo st) ctx'
        putStrLn ("Created absence type: " ++ name)

    AbsenceTypeList -> do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        putStr (displayAbsenceTypes ctx)

    AbsenceSetAllowance wid tid days -> requireAdmin st $ do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        let atId = AbsenceTypeId tid
            ctx' = ctx { acYearlyAllowance =
                Map.insert (WorkerId wid, atId) days (acYearlyAllowance ctx) }
        repoSaveAbsenceCtx (asRepo st) ctx'
        wname <- lookupWorkerName (asRepo st) (WorkerId wid)
        let tname = maybe (show tid) (T.unpack . atName) (Map.lookup atId (acTypes ctx))
        putStrLn ("Set " ++ wname ++ " allowance for " ++ tname
                  ++ ": " ++ show days ++ " days")

    -- Absence approval (admin)
    AbsenceApprove aid -> requireAdmin st $ do
        result <- SA.approveAbsenceService (asRepo st) (AbsenceId aid)
        case result of
            Right () -> putStrLn ("Approved absence #" ++ show aid)
            Left SA.AbsenceNotFound -> putStrLn "Absence not found."
            Left SA.AbsenceAllowanceExceeded -> putStrLn "Allowance exceeded. Use override if needed."
            Left err -> putStrLn ("Error: " ++ show err)

    AbsenceReject aid -> requireAdmin st $ do
        result <- SA.rejectAbsenceService (asRepo st) (AbsenceId aid)
        case result of
            Right () -> putStrLn ("Rejected absence #" ++ show aid)
            Left _   -> putStrLn "Absence not found."

    AbsenceListPending -> do
        reqs <- SA.listPendingAbsences (asRepo st)
        (wNames, tNames) <- absenceNameMaps (asRepo st)
        putStr (displayAbsences wNames tNames reqs)

    -- Absence request (worker or admin)
    CmdAbsenceRequest tid wid sd ed -> do
        let mStart = parseDay (T.unpack sd)
            mEnd   = parseDay (T.unpack ed)
        case (mStart, mEnd) of
            (Just s, Just e) -> do
                result <- SA.requestAbsenceService (asRepo st)
                    (WorkerId wid) (AbsenceTypeId tid) s e
                case result of
                    Right (AbsenceId aid) -> putStrLn ("Requested absence #" ++ show aid)
                    Left err -> putStrLn ("Error: " ++ show err)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    AbsenceListMine -> do
        reqs <- SA.listWorkerAbsences (asRepo st) (userWorkerId (asUser st))
                    (read "2020-01-01") (read "2030-12-31")
        (wNames, tNames) <- absenceNameMaps (asRepo st)
        putStr (displayAbsences wNames tNames reqs)

    VacationRemaining tid -> do
        mRemaining <- SA.vacationRemaining (asRepo st) (userWorkerId (asUser st))
                          (AbsenceTypeId tid) 2026
        case mRemaining of
            Nothing -> putStrLn "No yearly limit for this absence type."
            Just r  -> putStrLn ("Vacation days remaining: " ++ show r)

    -- Users (admin)
    UserCreate name pass role -> requireAdmin st $ do
        let r = case role of
                    "admin" -> Admin
                    _       -> Normal
        -- For user creation, we need a worker ID. Use next available.
        users <- repoListUsers (asRepo st)
        let nextWid = if null users
                      then 1
                      else maximum [w | User { userWorkerId = WorkerId w } <- users] + 1
        result <- register (asRepo st) (T.pack name) (T.pack pass) r (WorkerId nextWid)
        case result of
            Right (UserId uid) -> putStrLn ("Created user #" ++ show uid
                                            ++ " (Worker " ++ show nextWid ++ ")")
            Left UsernameTaken -> putStrLn "Username already taken."
            Left err -> putStrLn ("Error: " ++ show err)

    UserList -> do
        users <- repoListUsers (asRepo st)
        putStr (displayUsers users)

    UserDelete uid -> requireAdmin st $ do
        repoDeleteUser (asRepo st) (UserId uid)
        putStrLn ("Deleted user #" ++ show uid)

    -- Import / Export
    CmdExport file -> requireAdmin st $ do
        dat <- Export.gatherExport (asRepo st) Nothing
        BL.writeFile file (Export.encodeExport dat)
        let nSk = length (Export.expSkills dat)
            nSt = length (Export.expStations dat)
            nWk = length (Export.expWorkers dat)
            nSch = Map.size (Export.expSchedules dat)
        putStrLn ("Exported to " ++ file ++ ": "
                 ++ show nSk ++ " skills, "
                 ++ show nSt ++ " stations, "
                 ++ show nWk ++ " workers, "
                 ++ show nSch ++ " schedule(s)")

    CmdExportSchedule name file -> requireAdmin st $ do
        dat <- Export.gatherExport (asRepo st) (Just (T.pack name))
        BL.writeFile file (Export.encodeExport dat)
        let nAssign = sum $ map length $ Map.elems (Export.expSchedules dat)
        putStrLn ("Exported schedule '" ++ name ++ "' to " ++ file
                 ++ " (" ++ show nAssign ++ " assignments)")

    CmdImport file -> requireAdmin st $ do
        bs <- BL.readFile file
        case Export.decodeExport bs of
            Nothing -> putStrLn "Failed to parse JSON file."
            Just dat -> do
                msgs <- Export.applyImport (asRepo st) dat
                mapM_ putStrLn msgs
                putStrLn ("Import complete: " ++ show (length msgs) ++ " items.")

    -- Audit
    CmdAuditLog -> requireAdmin st $ do
        entries <- repoGetAuditLog (asRepo st)
        if null entries
            then putStrLn "  (no audit entries)"
            else mapM_ (\ae ->
                let cmdStr = case aeCommand ae of
                        Just c  -> c
                        Nothing -> Meta.render (auditEntryToMeta ae)
                in putStrLn ("  " ++ aeTimestamp ae ++ "  " ++ aeUsername ae ++ ": " ++ cmdStr)
                ) entries

    CmdReplay -> requireAdmin st $ do
        entries <- repoGetAuditLog (asRepo st)
        if null entries
            then putStrLn "  (no audit entries to replay)"
            else replayCommands fastReplay st (map auditEntryToTriple entries)

    CmdReplayFile file -> requireAdmin st $ do
        contents <- readFile file
        let cmds = lines contents
            entries = [(""::String, ""::String, c) | c <- cmds, not (null c)]
        if null entries
            then putStrLn "  (no commands in file)"
            else replayCommands fastReplay st entries

    CmdDemo -> requireAdmin st $ do
        -- Save the audit log before wiping
        entries <- repoGetAuditLog (asRepo st)
        if null entries
            then putStrLn "  (no audit entries to demo)"
            else do
                putStrLn ("Wiping database and replaying " ++ show (length entries) ++ " commands...")
                repoWipeAll (asRepo st)
                -- Re-create default admin
                _ <- register (asRepo st) (T.pack "admin") (T.pack "admin") Admin (WorkerId 1)
                putStrLn "Created default admin user (admin/admin), Worker 1"
                replayCommands fastReplay st (map auditEntryToTriple entries)
                putStrLn "Demo complete."

    -- Self
    PasswordChange -> do
        putStr "Old password: "
        hFlush stdout
        hSetEcho stdin False
        old <- getLine
        hSetEcho stdin True
        putStrLn ""
        putStr "New password: "
        hFlush stdout
        hSetEcho stdin False
        new <- getLine
        hSetEcho stdin True
        putStrLn ""
        result <- changePassword (asRepo st) (userId (asUser st)) (T.pack old) (T.pack new)
        case result of
            Right () -> putStrLn "Password changed."
            Left WrongOldPassword -> putStrLn "Wrong old password."
            Left err -> putStrLn ("Error: " ++ show err)

    -- Help
    Help -> printHelpSummary (userRole (asUser st))
    HelpGroup g -> printHelpGroup (userRole (asUser st)) g

    -- Context (stateless in web terminal, but handle gracefully)
    CmdUse typ ref -> handleUse st typ ref
    ContextView -> handleContextView st
    ContextClear -> handleContextClear st
    ContextClearType typ -> handleContextClearType st typ

    -- Checkpoints
    CheckpointCreate mName -> handleCheckpointCreate st mName
    CheckpointCommit -> handleCheckpointCommit st
    CheckpointRollback mName -> handleCheckpointRollback st mName
    CheckpointList -> handleCheckpointList st

    Unknown s -> putStrLn ("Unknown command: " ++ s ++ ". Type 'help' for available commands.")
    _ -> putStrLn "Command not handled."

requireAdmin :: AppState -> IO () -> IO ()
requireAdmin st action
    | userRole (asUser st) == Admin = action
    | otherwise = putStrLn "Permission denied. Admin required."

-- | Guard: require at least one active draft.
requireDraft :: AppState -> IO () -> IO ()
requireDraft st action = do
    drafts <- Draft.listDrafts (asRepo st)
    if null drafts
        then putStrLn "No active draft. Start a draft session first."
        else action

-- | Get the current audit checkpoint (max audit_log.id).
getCurrentCheckpoint :: Repository -> IO Int
getCurrentCheckpoint repo = do
    entries <- repoGetAuditLog repo
    return $ case entries of
        [] -> 0
        _  -> aeId (last entries)

-- | Auto-save the hint session to the database.
autoSaveHintSession :: AppState -> HintState -> IO ()
autoSaveHintSession st hs = do
    cp <- getCurrentCheckpoint (asRepo st)
    let hs' = hs { hstCheckpoint = cp, hstIsStale = False }
    repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs') (sessHints (hstSess hs')) cp
    writeIORef (asHintSession st) (Just hs')

-- | Get or lazily initialize the hint session. Handles stale sessions
-- by triggering auto-rebase when needed.
getOrInitSession :: AppState -> IO (Either String HintState)
getOrInitSession st = do
    mHs <- readIORef (asHintSession st)
    case mHs of
        Just hs | hstIsStale hs -> do
            -- Stale session: run auto-rebase
            putStrLn "Session is stale. Running rebase..."
            rebaseResult <- runRebase st hs
            case rebaseResult of
                Left err -> return (Left err)
                Right hs' -> return (Right hs')
        Just hs -> return (Right hs)
        Nothing -> do
            result <- initHintSession st
            case result of
                Left err -> return (Left err)
                Right hs -> do
                    writeIORef (asHintSession st) (Just hs)
                    return (Right hs)

-- | Build a SchedulerContext from the current draft and create a new hint session.
initHintSession :: AppState -> IO (Either String HintState)
initHintSession st = do
    resolved <- resolveDraftId (asRepo st) Nothing
    case resolved of
        Left err -> return (Left err)
        Right did -> do
            result <- buildSessionForDraft st did []
            case result of
                Left err -> return (Left err)
                Right sess -> do
                    cp <- getCurrentCheckpoint (asRepo st)
                    let hs = HintState sess did cp False
                    return (Right hs)

-- | Build a Session for a given draft, optionally applying existing hints.
buildSessionForDraft :: AppState -> Int -> [Hint] -> IO (Either String Session)
buildSessionForDraft st did hints = do
    mDraft <- Draft.loadDraft (asRepo st) did
    case mDraft of
        Nothing -> return (Left "Draft not found.")
        Just draft -> do
            let dateFrom = diDateFrom draft
                dateTo   = diDateTo draft
            users <- repoListUsers (asRepo st)
            let workers = Set.fromList [userWorkerId u | u <- users]
            let slots = Calendar.generateDateRangeSlots Calendar.defaultHours dateFrom dateTo Set.empty
            skillCtx   <- repoLoadSkillCtx (asRepo st)
            workerCtx  <- repoLoadWorkerCtx (asRepo st)
            absenceCtx <- repoLoadAbsenceCtx (asRepo st)
            cfg        <- repoLoadSchedulerConfig (asRepo st)
            shifts     <- repoLoadShifts (asRepo st)
            mPpc       <- SC.loadPayPeriodConfig (asRepo st)
            let ppc = maybe defaultPayPeriodConfig id mPpc
                periodBounds = payPeriodBounds ppc dateFrom
            calHrs <- Draft.computeCalendarHours (asRepo st) workerCtx
                          (fst periodBounds) (snd periodBounds)
            let closed = stationClosedSlots skillCtx slots
                ctx = Scheduler.SchedulerContext
                    { Scheduler.schSkillCtx    = skillCtx
                    , Scheduler.schWorkerCtx   = workerCtx
                    , Scheduler.schAbsenceCtx  = absenceCtx
                    , Scheduler.schSlots       = slots
                    , Scheduler.schWorkers     = workers
                    , Scheduler.schClosedSlots = closed
                    , Scheduler.schShifts      = shifts
                    , Scheduler.schPrevWeekendWorkers = Set.empty
                    , Scheduler.schConfig      = cfg
                    , Scheduler.schPeriodBounds = periodBounds
                    , Scheduler.schCalendarHours = calHrs
                    }
                baseSess = newSession ctx
                sess = foldl (flip addHint) baseSess hints
            return (Right sess)

-- | Run the rebase flow for a stale hint session.
runRebase :: AppState -> HintState -> IO (Either String HintState)
runRebase st hs = do
    entries <- repoAuditSince (asRepo st) (hstCheckpoint hs)
    let hints = sessHints (hstSess hs)
    -- Large gap detection
    if length entries > 50
        then handleLargeGap st hs hints
        else handleNormalRebase st hs entries hints

handleLargeGap :: AppState -> HintState -> [Hint] -> IO (Either String HintState)
handleLargeGap st hs hints = do
    putStrLn ("Significant changes since last save (" ++ "many mutations). [D]iscard / [F]orce resume?")
    putStr "> "
    hFlush stdout
    choice <- getLine
    case map toLower choice of
        "f" -> do
            rebuildResult <- buildSessionForDraft st (hstDraftId hs) hints
            case rebuildResult of
                Left err -> return (Left err)
                Right sess' -> do
                    cp <- getCurrentCheckpoint (asRepo st)
                    let hs' = HintState sess' (hstDraftId hs) cp False
                    repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs) hints cp
                    writeIORef (asHintSession st) (Just hs')
                    putStrLn "Force resumed. Session rebuilt from current context."
                    return (Right hs')
        _ -> do
            repoDeleteHintSession (asRepo st) (asSessionId st) (hstDraftId hs)
            writeIORef (asHintSession st) Nothing
            putStrLn "Hint session discarded."
            return (Left "Hint session discarded.")

handleNormalRebase :: AppState -> HintState -> [AuditEntry] -> [Hint] -> IO (Either String HintState)
handleNormalRebase st hs entries hints = do
    let result = rebaseSession (hstDraftId hs) entries hints
    case result of
        UpToDate -> do
            putStrLn "Hint session is up to date. No rebase needed."
            let hs' = hs { hstIsStale = False }
            writeIORef (asHintSession st) (Just hs')
            return (Right hs')
        AutoRebase n -> do
            -- Rebuild session from current context with existing hints
            rebuildResult <- buildSessionForDraft st (hstDraftId hs) hints
            case rebuildResult of
                Left err -> return (Left err)
                Right sess' -> do
                    cp <- getCurrentCheckpoint (asRepo st)
                    let hs' = HintState sess' (hstDraftId hs) cp False
                    repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs) hints cp
                    writeIORef (asHintSession st) (Just hs')
                    putStrLn ("Rebased over " ++ show n ++ " changes. All hints preserved.")
                    return (Right hs')
        HasConflicts classified -> do
            -- Show conflicts
            let conflicts = [(e, c) | (e, c) <- classified, c == Conflicting]
            putStrLn "Conflicts detected during rebase:"
            mapM_ (\(e, _) -> putStrLn ("  - " ++ maybe "?" id (aeCommand e))) conflicts
            putStrLn "[D]rop conflicting hints / [K]eep all (force) / [A]bort"
            putStr "> "
            hFlush stdout
            choice <- getLine
            case map toLower choice of
                "d" -> do
                    -- Drop hints that conflict
                    let conflictingEntries = [e | (e, Conflicting) <- classified]
                        safeHints = filter (\h -> not (any (\e -> classifyChange (hstDraftId hs) e [h] == Conflicting) conflictingEntries)) hints
                    rebuildResult <- buildSessionForDraft st (hstDraftId hs) safeHints
                    case rebuildResult of
                        Left err -> return (Left err)
                        Right sess' -> do
                            cp <- getCurrentCheckpoint (asRepo st)
                            let hs' = HintState sess' (hstDraftId hs) cp False
                            repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs) safeHints cp
                            writeIORef (asHintSession st) (Just hs')
                            let dropped = length hints - length safeHints
                            putStrLn ("Dropped " ++ show dropped ++ " conflicting hint(s). " ++ show (length safeHints) ++ " remaining.")
                            return (Right hs')
                "k" -> do
                    -- Force: keep all hints, rebuild from current context
                    rebuildResult <- buildSessionForDraft st (hstDraftId hs) hints
                    case rebuildResult of
                        Left err -> return (Left err)
                        Right sess' -> do
                            cp <- getCurrentCheckpoint (asRepo st)
                            let hs' = HintState sess' (hstDraftId hs) cp False
                            repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs) hints cp
                            writeIORef (asHintSession st) (Just hs')
                            putStrLn "Kept all hints. Session rebuilt from current context."
                            return (Right hs')
                _ -> do
                    putStrLn "Rebase aborted. Session unchanged."
                    return (Right hs)
        SessionInvalid msg -> do
            putStrLn msg
            repoDeleteHintSession (asRepo st) (asSessionId st) (hstDraftId hs)
            writeIORef (asHintSession st) Nothing
            return (Left "Hint session invalidated.")

-- | Load worker/station/skill name maps for display.
loadNameMaps :: AppState -> IO (Map.Map WorkerId String, Map.Map StationId String, Map.Map SkillId String)
loadNameMaps st = do
    users <- repoListUsers (asRepo st)
    stations <- SW.listStations (asRepo st)
    skills <- SW.listSkills (asRepo st)
    let workerNames = Map.fromList
            [ (userWorkerId u, T.unpack uname)
            | u <- users, let Username uname = userName u ]
        stationNames = Map.fromList
            [ (StationId sid, T.unpack sname)
            | (StationId sid, sname) <- stations ]
        skillNames = Map.fromList
            [ (sid, T.unpack (skillName sk))
            | (sid, sk) <- skills ]
    return (workerNames, stationNames, skillNames)

-- | After applying a hint permanently, remove it from the session and rebuild.
rebuildSessionAfterApply :: AppState -> HintState -> IO ()
rebuildSessionAfterApply st hs = do
    let remaining = init (sessHints (hstSess hs))  -- remove the last hint (just applied)
    rebuildResult <- buildSessionForDraft st (hstDraftId hs) remaining
    case rebuildResult of
        Left _ -> writeIORef (asHintSession st) Nothing
        Right sess' -> do
            cp <- getCurrentCheckpoint (asRepo st)
            let hs' = HintState sess' (hstDraftId hs) cp False
            repoSaveHintSession (asRepo st) (asSessionId st) (hstDraftId hs) remaining cp
            writeIORef (asHintSession st) (Just hs')

parseDay :: String -> Maybe Day
parseDay = parseTimeM True defaultTimeLocale "%Y-%m-%d"

showDayOfWeek :: DayOfWeek -> String
showDayOfWeek Monday    = "monday"
showDayOfWeek Tuesday   = "tuesday"
showDayOfWeek Wednesday = "wednesday"
showDayOfWeek Thursday  = "thursday"
showDayOfWeek Friday    = "friday"
showDayOfWeek Saturday  = "saturday"
showDayOfWeek Sunday    = "sunday"

showPinSpec :: PinSpec -> String
showPinSpec (PinSlot h)   = show h ++ ":00"
showPinSpec (PinShift sn) = T.unpack sn ++ " shift"

parseDayOfWeek :: String -> Maybe DayOfWeek
parseDayOfWeek s = case map toLower s of
    "monday"    -> Just Monday
    "tuesday"   -> Just Tuesday
    "wednesday" -> Just Wednesday
    "thursday"  -> Just Thursday
    "friday"    -> Just Friday
    "saturday"  -> Just Saturday
    "sunday"    -> Just Sunday
    "mon"       -> Just Monday
    "tue"       -> Just Tuesday
    "wed"       -> Just Wednesday
    "thu"       -> Just Thursday
    "fri"       -> Just Friday
    "sat"       -> Just Saturday
    "sun"       -> Just Sunday
    "m"         -> Just Monday
    "tu"        -> Just Tuesday
    "w"         -> Just Wednesday
    "th"        -> Just Thursday
    "f"         -> Just Friday
    "sa"        -> Just Saturday
    "su"        -> Just Sunday
    _           -> Nothing

-- | Replay options.
data ReplayOpts = ReplayOpts
    { roDelay :: !Int    -- ^ microseconds between commands (0 = instant)
    , roEcho  :: !Bool   -- ^ show a prompt-like prefix for each command
    }

-- | Fast replay (for interactive replay command).
fastReplay :: ReplayOpts
fastReplay = ReplayOpts 0 False

-- | Replay a list of (timestamp, username, command) entries.
-- Skips audit, replay, demo, and interactive commands to avoid loops.
replayCommands :: ReplayOpts -> AppState -> [(String, String, String)] -> IO ()
replayCommands opts st entries = do
    putStrLn ("Replaying " ++ show (length entries) ++ " commands...")
    mapM_ (\(ts, user, cmdStr) -> do
        when (roDelay opts > 0) $ threadDelay (roDelay opts)
        -- Comment lines: print as section headers, don't execute
        if take 1 cmdStr == "#"
        then putStrLn ("\n" ++ cmdStr)
        else do
            let label = if roEcho opts
                    then "admin> "
                    else if null ts then "" else "[" ++ ts ++ " " ++ user ++ "] "
            putStrLn (label ++ cmdStr)
            -- Resolve entity names before parsing
            resolved <- resolveInput (asRepo st) (asContext st) cmdStr
            let cmdStr' = case resolved of
                    Left _    -> cmdStr   -- fallback to original on resolution error
                    Right res -> res
                cmd = parseCommand cmdStr'
            case cmd of
                CmdAuditLog       -> putStrLn "  (skipped: audit)"
                CmdReplay         -> putStrLn "  (skipped: replay)"
                CmdReplayFile _   -> putStrLn "  (skipped: replay)"
                CmdDemo           -> putStrLn "  (skipped: demo)"
                PasswordChange    -> putStrLn "  (skipped: interactive)"
                Quit              -> putStrLn "  (skipped: quit)"
                Help              -> pure ()
                Unknown _         -> pure ()
                _                 -> handleCommand st cmd
        ) entries
    putStrLn "\nReplay complete."

-- | Convert an AuditEntry to a (timestamp, username, command) triple for replay.
-- Uses the raw command when present, falls back to render.
auditEntryToTriple :: AuditEntry -> (String, String, String)
auditEntryToTriple ae =
    let cmdStr = case aeCommand ae of
            Just c  -> c
            Nothing -> Meta.render (auditEntryToMeta ae)
    in (aeTimestamp ae, aeUsername ae, cmdStr)

-- | Convert an AuditEntry to a CommandMeta for rendering.
auditEntryToMeta :: AuditEntry -> Meta.CommandMeta
auditEntryToMeta ae = Meta.CommandMeta
    { Meta.cmEntityType = aeEntityType ae
    , Meta.cmOperation  = aeOperation ae
    , Meta.cmEntityId   = aeEntityId ae
    , Meta.cmTargetId   = aeTargetId ae
    , Meta.cmDateFrom   = aeDateFrom ae
    , Meta.cmDateTo     = aeDateTo ae
    , Meta.cmIsMutation = aeIsMutation ae
    , Meta.cmParams     = aeParams ae
    }

-- | Run demo mode: create admin, replay commands from a file with delay.
-- Called from Main when --demo flag is used.
runDemo :: Repository -> Int -> [String] -> IO ()
runDemo repo delayUs cmdLines = do
    -- Create default admin
    result <- register repo (T.pack "admin") (T.pack "admin") Admin (WorkerId 1)
    case result of
        Right _  -> putStrLn "Created default admin user (admin/admin)"
        Left err -> putStrLn ("Warning: " ++ show err)
    mUser <- repoGetUserByName repo (T.pack "admin")
    case mUser of
        Nothing -> putStrLn "ERROR: admin user not found after creation"
        Just adminUser -> do
            (demoSid, _tok) <- repoCreateSession repo (userId adminUser)
            st <- mkAppState repo adminUser demoSid
            let entries = [("", "", c) | c <- cmdLines]
                opts = ReplayOpts delayUs (delayUs > 0)
            replayCommands opts st entries
            -- Auto-export demo data
            dat <- Export.gatherExport repo Nothing
            let exportPath = "demo-export.json"
            BL.writeFile exportPath (Export.encodeExport dat)
            let nSk = length (Export.expSkills dat)
                nSt = length (Export.expStations dat)
                nWk = length (Export.expWorkers dat)
            putStrLn ("\nExported demo data to " ++ exportPath
                     ++ " (" ++ show nSk ++ " skills, "
                     ++ show nSt ++ " stations, "
                     ++ show nWk ++ " workers)")

-- -----------------------------------------------------------------
-- Session context commands
-- -----------------------------------------------------------------

parseEntityKind :: String -> Maybe EntityKind
parseEntityKind s = case map toLower s of
    "worker"       -> Just EWorker
    "skill"        -> Just ESkill
    "station"      -> Just EStation
    "absence-type" -> Just EAbsenceType
    _              -> Nothing

handleUse :: AppState -> String -> String -> IO ()
handleUse st typ ref =
    case parseEntityKind typ of
        Nothing -> putStrLn ("Unknown entity type: " ++ typ
                            ++ ". Valid types: worker, skill, station, absence-type")
        Just kind -> do
            result <- lookupByName (asRepo st) kind ref
            case result of
                Left err -> putStrLn err
                Right idStr -> do
                    let eid = read idStr :: Int
                    modifyIORef' (asContext st) (Map.insert kind (EntityRef eid ref))
                    putStrLn ("Context set: " ++ entityKindName kind
                             ++ " = " ++ ref ++ " (ID " ++ show eid ++ ")")

handleContextView :: AppState -> IO ()
handleContextView st = do
    ctx <- readIORef (asContext st)
    if Map.null ctx
        then putStrLn "No context set."
        else do
            putStrLn "Current context:"
            mapM_ (\(kind, EntityRef eid name) ->
                putStrLn ("  " ++ entityKindName kind
                         ++ ": " ++ name ++ " (ID " ++ show eid ++ ")")
                ) (Map.toList ctx)

handleContextClear :: AppState -> IO ()
handleContextClear st = do
    writeIORef (asContext st) emptyContext
    putStrLn "Context cleared."

handleContextClearType :: AppState -> String -> IO ()
handleContextClearType st typ =
    case parseEntityKind typ of
        Nothing -> putStrLn ("Unknown entity type: " ++ typ
                            ++ ". Valid types: worker, skill, station, absence-type")
        Just kind -> do
            modifyIORef' (asContext st) (Map.delete kind)
            putStrLn ("Cleared " ++ entityKindName kind ++ " context.")

-- -----------------------------------------------------------------
-- Checkpoint commands
-- -----------------------------------------------------------------

handleCheckpointCreate :: AppState -> Maybe String -> IO ()
handleCheckpointCreate st mName = do
    stack <- readIORef (asCheckpoints st)
    let name = case mName of
            Just n  -> n
            Nothing -> "checkpoint-" ++ show (length stack + 1)
    repoSavepoint (asRepo st) (T.pack name)
    writeIORef (asCheckpoints st) (name : stack)
    putStrLn ("Checkpoint created: " ++ name)

handleCheckpointCommit :: AppState -> IO ()
handleCheckpointCommit st = do
    stack <- readIORef (asCheckpoints st)
    case stack of
        [] -> putStrLn "No active checkpoint."
        (name : rest) -> do
            repoRelease (asRepo st) (T.pack name)
            writeIORef (asCheckpoints st) rest
            putStrLn ("Checkpoint committed: " ++ name)

handleCheckpointRollback :: AppState -> Maybe String -> IO ()
handleCheckpointRollback st mName = do
    stack <- readIORef (asCheckpoints st)
    case stack of
        [] -> putStrLn "No active checkpoint."
        (top : _) -> case mName of
            Nothing -> do
                repoRollbackTo (asRepo st) (T.pack top)
                putStrLn ("Rolled back to: " ++ top)
            Just target ->
                if target `elem` stack
                then do
                    -- Rollback to the named checkpoint, discard newer ones
                    repoRollbackTo (asRepo st) (T.pack target)
                    let trimmed = dropWhile (/= target) stack
                    writeIORef (asCheckpoints st) trimmed
                    putStrLn ("Rolled back to: " ++ target)
                else putStrLn ("Unknown checkpoint: " ++ target
                              ++ ". Active: " ++ unwords (reverse stack))

handleCheckpointList :: AppState -> IO ()
handleCheckpointList st = do
    stack <- readIORef (asCheckpoints st)
    case stack of
        [] -> putStrLn "No active checkpoints."
        _  -> do
            putStrLn "Active checkpoints:"
            mapM_ (\(i, name) ->
                putStrLn ("  " ++ show i ++ ". " ++ name)
                ) (zip [(1::Int)..] (reverse stack))

-- -----------------------------------------------------------------
-- Draft-id resolution
-- -----------------------------------------------------------------

-- | Resolve an optional draft-id string. If omitted, auto-select the
-- sole active draft. Error if 0 or 2+ drafts exist without an id.
resolveDraftId :: Repository -> Maybe String -> IO (Either String Int)
resolveDraftId repo Nothing = do
    drafts <- repoListDrafts repo
    case drafts of
        []  -> return (Left "No active drafts.")
        [d] -> return (Right (diId d))
        _   -> do
            let listing = unlines
                    [ "  #" ++ show (diId d) ++ ": "
                      ++ show (diDateFrom d) ++ " to " ++ show (diDateTo d)
                    | d <- drafts ]
            return (Left ("Multiple active drafts. Specify a draft-id:\n" ++ listing))
resolveDraftId _ (Just didStr) = return (Right (read didStr))

-- -----------------------------------------------------------------
-- Draft creation with freeze-line check
-- -----------------------------------------------------------------

createDraftWithFreezeCheck :: AppState -> Day -> Day -> Bool -> IO ()
createDraftWithFreezeCheck st dateFrom dateTo force = do
    freezeLine <- Freeze.computeFreezeLine
    unfreezes <- readIORef (asUnfreezes st)
    let frozen = Freeze.frozenDatesInRange freezeLine dateFrom dateTo
        stillFrozen = filter (not . Freeze.isDateUnfrozen unfreezes) frozen
    case stillFrozen of
        (firstFrozen : _) | not force -> do
            let lastFrozen = last' firstFrozen stillFrozen
            putStrLn ("This draft covers frozen dates (freeze line: "
                     ++ show freezeLine ++ ").")
            putStrLn ("  Frozen dates in range: " ++ show firstFrozen
                     ++ " to " ++ show lastFrozen)
            putStrLn ("  To unfreeze: calendar unfreeze "
                     ++ show firstFrozen ++ " " ++ show lastFrozen)
            putStrLn ("  To override: draft create "
                     ++ show dateFrom ++ " " ++ show dateTo ++ " --force")
        _ -> do
            result <- Draft.createDraft (asRepo st) dateFrom dateTo
            case result of
                Right did -> putStrLn ("Created draft #" ++ show did
                                      ++ " for " ++ show dateFrom ++ " to " ++ show dateTo)
                Left err  -> putStrLn ("Error: " ++ err)

-- -----------------------------------------------------------------
-- Help registry
-- -----------------------------------------------------------------

-- | (group, isAdminOnly, syntax, description)
type HelpEntry = (String, Bool, String, String)

helpRegistry :: [HelpEntry]
helpRegistry =
    -- Draft
      [ ("draft",    True,  "draft create <start> <end> [--force]",   "Create a draft for date range")
    , ("draft",    True,  "draft this-month",                        "Create draft for rest of month")
    , ("draft",    True,  "draft next-month",                        "Create draft for next month")
    , ("draft",    False, "draft list",                              "List active drafts")
    , ("draft",    False, "draft open <id>",                         "Show draft info")
    , ("draft",    False, "draft view [id]",                         "View draft assignments (table)")
    , ("draft",    False, "draft view-compact [id]",                 "View draft assignments (compact)")
    , ("draft",    True,  "draft generate [id]",                     "Run scheduler within draft")
    , ("draft",    True,  "draft commit [id] [note]",                "Commit draft to calendar")
    , ("draft",    True,  "draft discard [id]",                      "Discard draft")
    , ("draft",    False, "draft hours [id]",                        "Worker hours summary for draft")
    , ("draft",    False, "draft diagnose [id]",                     "Diagnose draft")
    -- Calendar
    , ("calendar", False, "calendar view <start> <end>",            "View calendar (table)")
    , ("calendar", False, "calendar view-by-worker <start> <end>",  "View calendar grouped by worker")
    , ("calendar", False, "calendar view-by-station <start> <end>", "View calendar grouped by station")
    , ("calendar", False, "calendar view-compact <start> <end>",    "View calendar (compact, 100-col)")
    , ("calendar", False, "calendar hours <start> <end>",           "Worker hours summary")
    , ("calendar", False, "calendar diagnose <start> <end>",        "Diagnose unfilled positions")
    , ("calendar", True,  "calendar commit <name> <start> <end> [note]", "Commit named schedule to calendar")
    , ("calendar", False, "calendar history",                       "List calendar commits")
    , ("calendar", False, "calendar history <id>",                  "View historical snapshot")
    , ("calendar", True,  "calendar unfreeze <date>",              "Temporarily unfreeze a date")
    , ("calendar", True,  "calendar unfreeze <start> <end>",       "Temporarily unfreeze a date range")
    , ("calendar", False, "calendar freeze-status",                "Show freeze line and unfreezes")
    -- Schedule (user)
    , ("schedule", False, "schedule list",                   "List saved schedules")
    , ("schedule", False, "schedule view <name>",            "View a schedule (table)")
    , ("schedule", False, "schedule view-by-worker <name>",  "View schedule grouped by worker")
    , ("schedule", False, "schedule view-by-station <name>", "View schedule grouped by station")
    , ("schedule", False, "schedule hours <name>",           "Worker hours summary")
    , ("schedule", False, "schedule view-compact <name>",     "View schedule (compact, 100-col)")
    , ("schedule", False, "schedule diagnose <name>",        "Diagnose unfilled positions")
    -- Schedule (admin)
    , ("schedule", True,  "schedule create <name> <date>",   "Create schedule (week of date)")
    , ("schedule", True,  "schedule delete <name>",          "Delete a schedule")
    , ("schedule", True,  "schedule clear <name>",           "Clear all assignments")
    , ("schedule", True,  "assign <sched> <wid> <sid> <date> <hour>", "Assign worker to station/slot")
    , ("schedule", True,  "unassign <sched> <wid> <sid> <date> <hour>", "Remove assignment")
    -- Skill
    , ("skill",    True,  "skill create <id> <name>",        "Create a skill")
    , ("skill",    True,  "skill rename <id> <name>",        "Rename a skill")
    , ("skill",    True,  "skill delete <id>",               "Delete a skill (fails if referenced)")
    , ("skill",    True,  "skill force-delete <id>",         "Remove all references and delete skill")
    , ("skill",    False, "skill list",                      "List all skills")
    , ("skill",    False, "skill view <id>",                 "View details of a skill")
    , ("skill",    True,  "skill implication <a> <b>",       "Skill A implies skill B")
    , ("skill",    True,  "skill remove-implication <a> <b>", "Remove implication")
    , ("skill",    False, "skill info",                      "Show skill context")
    -- Station
    , ("station",  True,  "station add <id> <name>",         "Add a station")
    , ("station",  False, "station list",                    "List stations")
    , ("station",  True,  "station remove <id>",             "Remove a station")
    , ("station",  True,  "station set-hours <id> <start> <end>", "Set station operating hours")
    , ("station",  True,  "station close-day <id> <day>",    "Close station on day of week")
    , ("station",  True,  "station set-multi-hours <id> <start> <end>", "Set multi-station hours")
    , ("station",  True,  "station require-skill <sid> <skid>", "Require skill for station")
    , ("station",  True,  "station remove-required-skill <sid> <skid>", "Remove required skill from station")
    -- Worker
    , ("worker",   True,  "worker grant-skill <wid> <sid>",  "Grant skill to worker")
    , ("worker",   True,  "worker revoke-skill <wid> <sid>", "Revoke skill from worker")
    , ("worker",   True,  "worker set-hours <wid> <hours>",  "Set max per-period hours")
    , ("worker",   True,  "worker set-overtime <wid> <on|off>", "Toggle overtime opt-in")
    , ("worker",   True,  "worker set-prefs <wid> <sid...>", "Set station preferences")
    , ("worker",   True,  "worker set-shift-pref <wid> <shift...>", "Set shift preferences")
    , ("worker",   True,  "worker set-weekend-only <wid> <on|off>", "Mark worker as weekend-only")
    , ("worker",   True,  "worker set-variety <wid> <on|off>", "Toggle variety preference")
    , ("worker",   True,  "worker set-status <wid> <status>", "Set employment status preset (salaried|full-time|part-time|per-diem)")
    , ("worker",   True,  "worker set-overtime-model <wid> <model>", "Set overtime model (eligible|manual-only|exempt)")
    , ("worker",   True,  "worker set-pay-tracking <wid> <mode>", "Set pay tracking (standard|exempt)")
    , ("worker",   True,  "worker set-temp <wid> <on|off>", "Toggle temp worker flag")
    , ("worker",   True,  "worker set-seniority <wid> <level>", "Set seniority level")
    , ("worker",   True,  "worker set-cross-training <wid> <sid>", "Add cross-training goal")
    , ("worker",   True,  "worker clear-cross-training <wid> <sid>", "Remove cross-training goal")
    , ("worker",   True,  "worker avoid-pairing <w1> <w2>",  "Prevent concurrent scheduling")
    , ("worker",   True,  "worker clear-avoid-pairing <w1> <w2>", "Clear avoid-pairing")
    , ("worker",   True,  "worker prefer-pairing <w1> <w2>", "Prefer concurrent scheduling")
    , ("worker",   True,  "worker clear-prefer-pairing <w1> <w2>", "Clear prefer-pairing")
    , ("worker",   False, "worker info",                     "Show worker context")
    -- Shift
    , ("shift",    True,  "shift create <name> <start> <end>", "Create a shift (hours)")
    , ("shift",    False, "shift list",                      "List configured shifts")
    , ("shift",    True,  "shift delete <name>",             "Delete a shift")
    -- Absence
    , ("absence",  False, "absence request <tid> <wid> <start> <end>", "Request an absence")
    , ("absence",  False, "absence list",                    "List your absences")
    , ("absence",  False, "vacation remaining <tid>",        "Check remaining vacation days")
    , ("absence",  True,  "absence-type create <name> <on|off>", "Create absence type")
    , ("absence",  True,  "absence-type list",               "List absence types")
    , ("absence",  True,  "absence set-allowance <wid> <tid> <days>", "Set worker allowance")
    , ("absence",  True,  "absence approve <id>",            "Approve absence request")
    , ("absence",  True,  "absence reject <id>",             "Reject absence request")
    , ("absence",  True,  "absence list-pending",            "List pending requests")
    -- Config
    , ("config",   True,  "config show",                     "Show scheduler config")
    , ("config",   True,  "config set <key> <value>",        "Set a config parameter")
    , ("config",   True,  "config preset <name>",            "Apply a named preset")
    , ("config",   True,  "config preset-list",              "List available presets")
    , ("config",   True,  "config reset",                    "Reset config to defaults")
    , ("config",   True,  "config set-pay-period <type> <anchor>", "Set pay period (weekly|biweekly|semi-monthly|monthly)")
    , ("config",   False, "config show-pay-period",          "Show pay period config and current period")
    -- Pin
    , ("pin",      True,  "pin <wid> <sid> <day> <hour|shift>", "Pin worker to station/slot")
    , ("pin",      True,  "unpin <wid> <sid> <day> <hour|shift>", "Remove pin")
    , ("pin",      True,  "pin list",                        "List pinned assignments")
    -- What-if
    , ("what-if",  True,  "what-if close-station <sid> <date> <hour>",      "What if we close a station at a slot?")
    , ("what-if",  True,  "what-if pin <wid> <sid> <date> <hour>",         "What if we pin a worker to a slot?")
    , ("what-if",  True,  "what-if add-worker <name> <skills...> [hours]", "What if we bring in a temp worker?")
    , ("what-if",  True,  "what-if waive-overtime <wid>",                  "What if we waive overtime for a worker?")
    , ("what-if",  True,  "what-if grant-skill <wid> <sid>",              "What if a worker had this skill?")
    , ("what-if",  True,  "what-if override-prefs <wid> <sid...>",        "What if we change preferences?")
    , ("what-if",  True,  "what-if revert",                                "Undo the last hint")
    , ("what-if",  True,  "what-if revert-all",                            "Undo all hints")
    , ("what-if",  True,  "what-if list",                                  "List all applied hints")
    , ("what-if",  True,  "what-if apply",                                 "Apply last hint permanently")
    , ("what-if",  True,  "what-if rebase",                                "Reconcile hints with data changes")
    -- Export
    , ("export",   True,  "export <file>",                   "Export all data to JSON")
    , ("export",   True,  "export <schedule> <file>",        "Export one schedule to JSON")
    , ("export",   True,  "import <file>",                   "Import data from JSON")
    -- Audit
    , ("audit",    True,  "audit",                           "Show audit trail")
    , ("audit",    True,  "replay",                          "Replay audit log")
    , ("audit",    True,  "replay <file>",                   "Replay commands from file")
    , ("audit",    True,  "demo",                            "Wipe DB and replay audit log")
    -- User
    , ("user",     True,  "user create <name> <pass> <role>", "Create a user")
    , ("user",     True,  "user list",                       "List all users")
    , ("user",     True,  "user delete <id>",                "Delete a user")
    -- Context
    , ("context",  False, "use <type> <name|id>",            "Set session context (worker/skill/station/absence-type)")
    , ("context",  False, "context view",                    "Show current context")
    , ("context",  False, "context clear",                   "Clear all context")
    , ("context",  False, "context clear <type>",            "Clear context for one type")
    -- Checkpoint
    , ("checkpoint", False, "checkpoint create [name]",      "Create a checkpoint (savepoint)")
    , ("checkpoint", False, "checkpoint commit",             "Commit most recent checkpoint")
    , ("checkpoint", False, "checkpoint rollback [name]",    "Rollback to checkpoint")
    , ("checkpoint", False, "checkpoint list",               "List active checkpoints")
    -- General
    , ("general",  False, "password change",                 "Change your password")
    , ("general",  False, "help",                            "Show command groups")
    , ("general",  False, "help <group>",                    "Show commands in a group")
    , ("general",  False, "quit",                            "Exit")
    ]

-- | (group, description)
helpGroups :: [(String, String)]
helpGroups =
    [ ("draft",    "Draft scheduling sessions (staging area)")
    , ("calendar", "Calendar viewing, committing, and history")
    , ("schedule", "Schedule creation, viewing, and management")
    , ("worker",   "Worker skills, hours, preferences, and pairings")
    , ("skill",    "Skill definitions and implications")
    , ("station",  "Station setup, hours, and requirements")
    , ("shift",    "Shift definitions")
    , ("absence",  "Absence types, requests, and approvals")
    , ("config",   "Scheduler configuration and presets")
    , ("pin",      "Pinned assignments")
    , ("what-if",  "What-if hint exploration within drafts")
    , ("context",  "Session context (use, view, clear)")
    , ("checkpoint", "Checkpoint, commit, and rollback")
    , ("export",   "JSON import and export")
    , ("audit",    "Audit trail and replay")
    , ("user",     "User account management")
    , ("general",  "Help, password, and exit")
    ]

displaySkillRefs :: SW.SkillReferences -> IO ()
displaySkillRefs refs = do
    forM_ (SW.srWorkers refs) $ \(_wid, name) ->
        putStrLn ("  " ++ name ++ " has this skill")
    forM_ (SW.srStations refs) $ \(_stid, name) ->
        putStrLn ("  " ++ name ++ " requires this skill")
    forM_ (SW.srCrossTraining refs) $ \(_wid, name) ->
        putStrLn ("  " ++ name ++ " cross-training toward this skill")
    forM_ (SW.srImpliedBy refs) $ \(_sid, name) ->
        putStrLn ("  " ++ name ++ " implies this skill")
    forM_ (SW.srImplies refs) $ \(_sid, name) ->
        putStrLn ("  This skill implies " ++ name)

printHelpSummary :: Role -> IO ()
printHelpSummary role = do
    putStrLn "Command groups (type 'help <group>' for details):"
    putStrLn ""
    let groups = if role == Admin then helpGroups
                 else filter (\(g, _) -> hasUserCommands g) helpGroups
        nameW = maximum (0 : [length g | (g, _) <- groups]) + 2
    mapM_ (\(g, desc) ->
        putStrLn ("  " ++ padRight nameW g ++ desc)
        ) groups
  where
    hasUserCommands g = any (\(g', adm, _, _) -> g' == g && not adm) helpRegistry

printHelpGroup :: Role -> String -> IO ()
printHelpGroup role group =
    let g = map toLower group
        matching = [ (syn, desc)
                   | (g', adm, syn, desc) <- helpRegistry
                   , g' == g
                   , not adm || role == Admin
                   ]
        validGroups = map fst helpGroups
    in case matching of
        [] | g `elem` validGroups -> putStrLn ("  (no commands available in '" ++ group ++ "' for your role)")
           | otherwise -> putStrLn ("Unknown group: " ++ group
                                    ++ ". Available: " ++ unwords validGroups)
        cmds -> do
            let synW = maximum (0 : [length syn | (syn, _) <- cmds]) + 2
            mapM_ (\(syn, desc) ->
                putStrLn ("  " ++ padRight synW syn ++ desc)
                ) cmds

when :: Bool -> IO () -> IO ()
when True  action = action
when False _      = return ()

lookupWorkerName :: Repository -> WorkerId -> IO String
lookupWorkerName repo wid = do
    users <- repoListUsers repo
    case [u | u <- users, userWorkerId u == wid] of
        (u:_) -> let Username uname = userName u in return (T.unpack uname)
        []    -> let WorkerId w = wid in return ("Worker " ++ show w)

lookupSkillName :: Repository -> SkillId -> IO String
lookupSkillName repo sid = do
    skills <- repoListSkills repo
    case [sk | (sid', sk) <- skills, sid' == sid] of
        (sk:_) -> return (T.unpack (skillName sk))
        []     -> let SkillId s = sid in return ("Skill " ++ show s)

absenceNameMaps :: Repository -> IO (Map.Map WorkerId String, Map.Map AbsenceTypeId String)
absenceNameMaps repo = do
    users <- repoListUsers repo
    ctx <- repoLoadAbsenceCtx repo
    let wNames = Map.fromList
            [ (userWorkerId u, T.unpack uname)
            | u <- users, let Username uname = userName u ]
        tNames = Map.fromList
            [ (tid, T.unpack (atName at))
            | (tid, at) <- Map.toList (acTypes ctx) ]
    return (wNames, tNames)

-- -----------------------------------------------------------------
-- Draft validation display
-- -----------------------------------------------------------------

-- | Display a violation report grouped by worker.
displayViolationReport :: DraftInfo -> Map.Map WorkerId String
                       -> Map.Map StationId String
                       -> [DraftViolation] -> IO ()
displayViolationReport draft workerNames stationNames violations = do
    let nRemoved = length violations
    putStrLn ("Draft #" ++ show (diId draft) ++ " validated against updated calendar.")
    putStrLn (show nRemoved ++ " assignment" ++ (if nRemoved == 1 then "" else "s")
             ++ " removed due to constraint violations:")
    putStrLn ""
    -- Group by worker
    let grouped = Map.toAscList $ foldl (\acc v ->
            let w = assignWorker (dvAssignment v)
            in Map.insertWith (++) w [v] acc) Map.empty violations
    mapM_ (\(wid@(WorkerId widN), vs) -> do
        let wName = Map.findWithDefault ("Worker " ++ show widN) wid workerNames
        putStrLn ("  " ++ wName ++ ":")
        mapM_ (\v ->
            let a = dvAssignment v
                s = assignSlot a
                sid = assignStation a
                sName = Map.findWithDefault ("station " ++ show (let StationId n = sid in n)) sid stationNames
            in putStrLn ("    - " ++ show (slotDate s)
                        ++ " " ++ sName
                        ++ " " ++ show (slotStart s)
                        ++ ": " ++ dvConstraint v)
            ) vs
        ) grouped
    putStrLn ""
    putStrLn "Run 'diagnose' to see how to fill the gaps."

-- | Show a Double with 1 decimal place.
showFFloat1 :: Double -> String
showFFloat1 x = show (fromIntegral (round (x * 10) :: Integer) / 10.0 :: Double)

-- | Safe version of 'last' with a default value.
last' :: a -> [a] -> a
last' def [] = def
last' _   xs = last xs
