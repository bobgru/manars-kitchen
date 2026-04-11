module CLI.App
    ( AppState(..)
    , mkAppState
    , runRepl
    , runDemo
    ) where

import System.IO (hFlush, stdout, hSetEcho, stdin)
import Control.Concurrent (threadDelay)
import Data.Char (toLower)
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.ByteString.Lazy as BL
import Data.Time
    ( Day, DayOfWeek(..), TimeOfDay(..), parseTimeM, defaultTimeLocale
    , addDays, fromGregorian, toGregorian, gregorianMonthLength
    )
import Data.Time.Clock (getCurrentTime, utctDay)

import Domain.Types
import qualified Domain.Shift
import Domain.Shift (ShiftDef(..))
import Domain.Skill (Skill(..), SkillContext(..), stationClosedSlots)
import qualified Domain.Scheduler as Scheduler
import qualified Domain.Diagnosis as Diagnosis
import qualified Domain.Calendar as Calendar
import Domain.Worker (WorkerContext(..))
import Domain.SchedulerConfig (presetNames, configToMap)
import Domain.Pin (expandPins, PinnedAssignment(..), PinSpec(..))
import Domain.Absence
    ( AbsenceType(..), AbsenceContext(..)
    )
import Auth.Types (User(..), UserId(..), Username(..), Role(..))
import Repo.Types (Repository(..), CalendarCommit(..), DraftInfo(..))
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
import CLI.Commands (Command(..), parseCommand)
import CLI.Display
import CLI.Resolve
    ( EntityKind(..), EntityRef(..), SessionContext
    , emptyContext, resolveInput, lookupByName, entityKindName
    )

data AppState = AppState
    { asRepo       :: !Repository
    , asUser       :: !User
    , asContext    :: !(IORef SessionContext)
    , asCheckpoints :: !(IORef [String])
    , asUnfreezes  :: !(IORef (Set.Set (Day, Day)))
    }

-- | Create an AppState with initialized IORefs.
mkAppState :: Repository -> User -> IO AppState
mkAppState repo user = do
    ctxRef <- newIORef emptyContext
    cpRef  <- newIORef []
    ufRef  <- newIORef Set.empty
    return (AppState repo user ctxRef cpRef ufRef)

runRepl :: AppState -> IO ()
runRepl st = do
    let Username uname = userName (asUser st)
        role = if userRole (asUser st) == Admin then "admin" else "user"
    putStr (uname ++ " [" ++ role ++ "]> ")
    hFlush stdout
    line <- getLine
    -- Quick-parse for commands that don't need resolution
    case parseCommand line of
        Quit -> putStrLn "Goodbye."
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
                    when (isMutating cmd) $
                        repoLogCommand (asRepo st) uname line  -- log original input
                    handleCommand st cmd
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
            else mapM_ (\n -> putStrLn ("  " ++ n)) names

    ScheduleView name -> do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> do
                users <- repoListUsers (asRepo st)
                stations <- SW.listStations (asRepo st)
                skillCtx <- repoLoadSkillCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, sname)
                        | (StationId sid, sname) <- stations ]
                putStr (displayScheduleTable workerNames stationNames
                           Calendar.defaultHours (scStationHours skillCtx) s)

    ScheduleViewCompact name -> do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> do
                users <- repoListUsers (asRepo st)
                stations <- SW.listStations (asRepo st)
                skillCtx <- repoLoadSkillCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, sname)
                        | (StationId sid, sname) <- stations ]
                putStr (displayScheduleCompact workerNames stationNames
                           Calendar.defaultHours (scStationHours skillCtx) s)

    ScheduleViewByWorker name -> do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> putStr (displayScheduleByWorker s)

    ScheduleViewByStation name -> do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just s  -> putStr (displayScheduleByStation s)

    ScheduleDelete name -> requireAdmin st $ do
        repoDeleteSchedule (asRepo st) name
        putStrLn ("Deleted schedule: " ++ name)

    ScheduleHours name -> do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just sched -> do
                users <- repoListUsers (asRepo st)
                workerCtx <- repoLoadWorkerCtx (asRepo st)
                let workerNames = Map.fromList
                        [ (userWorkerId u, uname)
                        | u <- users, let Username uname = userName u ]
                putStr (displayWorkerHours workerNames
                           (wcMaxWeeklyHours workerCtx)
                           sched)

    ScheduleDiagnose name -> do
        ms <- repoLoadSchedule (asRepo st) name
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
                        }
                    result = Scheduler.buildScheduleFrom sched ctx
                    diags = Diagnosis.diagnose result ctx
                    workerNames = Map.fromList
                        [ (userWorkerId u, uname)
                        | u <- users, let Username uname = userName u ]
                    stationNames = Map.fromList
                        [ (StationId sid, sname)
                        | (StationId sid, sname) <- stations ]
                    skillNames = Map.fromList
                        [ (sid, skillName sk)
                        | (sid, sk) <- skills ]
                putStr (displayDiagnosis workerNames stationNames skillNames result diags)

    ScheduleClear name -> requireAdmin st $ do
        ms <- repoLoadSchedule (asRepo st) name
        case ms of
            Nothing -> putStrLn "Schedule not found."
            Just _  -> do
                repoSaveSchedule (asRepo st) name (Schedule Set.empty)
                putStrLn ("Cleared schedule: " ++ name)

    CmdAssign sched wid sid dateStr hr -> requireAdmin st $ do
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                ms <- repoLoadSchedule (asRepo st) sched
                case ms of
                    Nothing -> putStrLn "Schedule not found."
                    Just (Schedule as) -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            a = Assignment (WorkerId wid) (StationId sid) slot
                            sched' = Schedule (Set.insert a as)
                        repoSaveSchedule (asRepo st) sched sched'
                        putStrLn ("Assigned Worker " ++ show wid
                                 ++ " to Station " ++ show sid
                                 ++ " at " ++ dateStr ++ " " ++ show hr ++ ":00")

    CmdUnassign sched wid sid dateStr hr -> requireAdmin st $ do
        case parseDay dateStr of
            Nothing -> putStrLn "Invalid date format. Use YYYY-MM-DD."
            Just day -> do
                ms <- repoLoadSchedule (asRepo st) sched
                case ms of
                    Nothing -> putStrLn "Schedule not found."
                    Just (Schedule as) -> do
                        let slot = Slot day (TimeOfDay hr 0 0) 3600
                            a = Assignment (WorkerId wid) (StationId sid) slot
                            sched' = Schedule (Set.delete a as)
                        repoSaveSchedule (asRepo st) sched sched'
                        putStrLn ("Unassigned Worker " ++ show wid
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
                                }
                        result <- Opt.optimizeSchedule ctx seed $ \progress ->
                            let phaseStr = case opPhase progress of
                                    PhaseHard -> "hard"
                                    PhaseSoft -> "soft"
                                elapsed = showFFloat1 (opElapsedSecs progress)
                            in putStrLn ("[opt] phase=" ++ phaseStr
                                        ++ " iter=" ++ show (opIteration progress)
                                        ++ " unfilled=" ++ show (opBestUnfilled progress)
                                        ++ " score=" ++ showFFloat1 (opBestScore progress)
                                        ++ " elapsed=" ++ elapsed ++ "s")
                        let sched  = Scheduler.srSchedule result
                            unfilled = Scheduler.srUnfilled result
                            truly = length [u | u <- unfilled, Scheduler.unfilledKind u == Scheduler.TrulyUnfilled]
                            under = length unfilled - truly
                        repoSaveSchedule (asRepo st) name sched
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
                                ++ diCreatedAt d)
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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList stations
                        displayViolationReport d workerNames stationNames violations
                        putStrLn ""
                -- Load (possibly updated) draft assignments
                sched <- repoLoadDraftAssignments (asRepo st) did
                putStrLn ("Draft #" ++ show (diId d))
                putStrLn ("  Date range: " ++ show (diDateFrom d) ++ " to " ++ show (diDateTo d))
                putStrLn ("  Created at: " ++ diCreatedAt d)
                putStrLn ("  Assignments: " ++ show (Set.size (unSchedule sched)))

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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
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
                let note = maybe "" id mNote
                result <- Draft.commitDraft (asRepo st) did note
                case result of
                    Left err  -> putStrLn ("Error: " ++ err)
                    Right ()  -> do
                        putStrLn ("Draft #" ++ show did ++ " committed to calendar.")
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
                    Right ()  -> putStrLn ("Draft #" ++ show did ++ " discarded.")

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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                        putStr (displayWorkerHours workerNames
                                   (wcMaxWeeklyHours workerCtx) sched)

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
                                }
                            result = Scheduler.buildScheduleFrom sched ctx
                            diags = Diagnosis.diagnose result ctx
                            workerNames = Map.fromList
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
                                | (StationId sid, sname) <- stations ]
                            skillNames = Map.fromList
                                [ (sid, skillName sk)
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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
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
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                        putStr (displayWorkerHours workerNames
                                   (wcMaxWeeklyHours workerCtx) sched)
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
                                }
                            result = Scheduler.buildScheduleFrom sched ctx
                            diags = Diagnosis.diagnose result ctx
                            workerNames = Map.fromList
                                [ (userWorkerId u, uname)
                                | u <- users, let Username uname = userName u ]
                            stationNames = Map.fromList
                                [ (StationId sid, sname)
                                | (StationId sid, sname) <- stations ]
                            skillNames = Map.fromList
                                [ (sid, skillName sk)
                                | (sid, sk) <- skills ]
                        putStr (displayDiagnosis workerNames stationNames skillNames result diags)
            _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    CalendarDoCommit name startStr endStr mNote -> requireAdmin st $
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                ms <- repoLoadSchedule (asRepo st) name
                case ms of
                    Nothing -> putStrLn ("Schedule not found: " ++ name)
                    Just sched -> do
                        let note = maybe "" id mNote
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
                                ++ padRight 22 (ccCommittedAt c)
                                ++ ccNote c)
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

    -- Stations (admin)
    StationAdd sid name -> requireAdmin st $ do
        SW.addStation (asRepo st) (StationId sid) name
        putStrLn ("Added Station " ++ show sid ++ " (" ++ name ++ ")")

    StationList -> do
        stations <- SW.listStations (asRepo st)
        if null stations
            then putStrLn "  (no stations)"
            else mapM_ (\(StationId sid, name) ->
                putStrLn ("  Station " ++ show sid ++ ": " ++ name)
                ) stations

    StationRemove sid -> requireAdmin st $ do
        SW.removeStation (asRepo st) (StationId sid)
        putStrLn ("Removed Station " ++ show sid)

    StationSetHours sid sh eh -> requireAdmin st $ do
        SW.setStationHours (asRepo st) (StationId sid) sh eh
        putStrLn ("Set Station " ++ show sid ++ " hours: " ++ show sh ++ ":00-" ++ show eh ++ ":00")

    StationSetMultiHours sid sh eh -> requireAdmin st $ do
        SW.setMultiStationHours (asRepo st) (StationId sid) sh eh
        putStrLn ("Set Station " ++ show sid ++ " multi-station hours: " ++ show sh ++ ":00-" ++ show eh ++ ":00")

    StationCloseDay sid dayStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                SW.closeStationDay (asRepo st) (StationId sid) dow
                putStrLn ("Station " ++ show sid ++ " closed on " ++ dayStr)

    StationRequireSkill sid skid -> requireAdmin st $ do
        ctx <- repoLoadSkillCtx (asRepo st)
        let current = Map.findWithDefault Set.empty (StationId sid) (scStationRequires ctx)
        SW.setStationRequiredSkills (asRepo st) (StationId sid) (Set.insert (SkillId skid) current)
        putStrLn ("Station " ++ show sid ++ " now requires Skill " ++ show skid)

    SkillCreate sid name -> requireAdmin st $ do
        SW.addSkill (asRepo st) (SkillId sid) name ""
        putStrLn ("Created Skill " ++ show sid ++ " (" ++ name ++ ")")

    SkillList -> do
        skills <- SW.listSkills (asRepo st)
        if null skills
            then putStrLn "  (no skills)"
            else mapM_ (\(SkillId sid, sk) ->
                putStrLn ("  Skill " ++ show sid ++ ": " ++ Domain.Skill.skillName sk)
                ) skills

    SkillImplication a b -> requireAdmin st $ do
        SW.addSkillImplication (asRepo st) (SkillId a) (SkillId b)
        putStrLn ("Skill " ++ show a ++ " now implies Skill " ++ show b)

    SkillInfo -> do
        ctx <- repoLoadSkillCtx (asRepo st)
        putStr (displaySkillCtx ctx)

    -- Worker skills (admin)
    WorkerGrantSkill wid sid -> requireAdmin st $ do
        SW.grantWorkerSkill (asRepo st) (WorkerId wid) (SkillId sid)
        putStrLn ("Granted Skill " ++ show sid ++ " to Worker " ++ show wid)

    WorkerRevokeSkill wid sid -> requireAdmin st $ do
        SW.revokeWorkerSkill (asRepo st) (WorkerId wid) (SkillId sid)
        putStrLn ("Revoked Skill " ++ show sid ++ " from Worker " ++ show wid)

    -- Worker context (admin)
    WorkerSetHours wid h -> requireAdmin st $ do
        SW.setMaxHours (asRepo st) (WorkerId wid) (fromIntegral (h * 3600))
        putStrLn ("Set Worker " ++ show wid ++ " max hours: " ++ show h ++ "h/week")

    WorkerSetOvertime wid b -> requireAdmin st $ do
        SW.setOvertimeOptIn (asRepo st) (WorkerId wid) b
        putStrLn ("Worker " ++ show wid ++ " overtime: " ++ if b then "on" else "off")

    WorkerSetPrefs wid sids -> requireAdmin st $ do
        SW.setStationPreferences (asRepo st) (WorkerId wid) (map StationId sids)
        putStrLn ("Set Worker " ++ show wid ++ " preferences")

    WorkerSetVariety wid b -> requireAdmin st $ do
        SW.setVarietyPreference (asRepo st) (WorkerId wid) b
        putStrLn ("Worker " ++ show wid ++ " variety: " ++ if b then "on" else "off")

    WorkerSetShiftPref wid names -> requireAdmin st $ do
        SW.setShiftPreferences (asRepo st) (WorkerId wid) names
        putStrLn ("Set Worker " ++ show wid ++ " shift prefs: " ++ unwords names)

    WorkerSetWeekendOnly wid b -> requireAdmin st $ do
        SW.setWeekendOnly (asRepo st) (WorkerId wid) b
        putStrLn ("Worker " ++ show wid ++ " weekend-only: " ++ if b then "on" else "off")

    WorkerInfo -> do
        ctx <- repoLoadWorkerCtx (asRepo st)
        putStr (displayWorkerCtx ctx)

    WorkerSetSeniority wid lvl -> requireAdmin st $ do
        SW.setSeniority (asRepo st) (WorkerId wid) lvl
        putStrLn ("Set Worker " ++ show wid ++ " seniority level: " ++ show lvl)

    WorkerSetCrossTraining wid sid -> requireAdmin st $ do
        SW.addCrossTraining (asRepo st) (WorkerId wid) (SkillId sid)
        putStrLn ("Added cross-training goal: Worker " ++ show wid ++ " -> Skill " ++ show sid)

    WorkerClearCrossTraining wid sid -> requireAdmin st $ do
        SW.removeCrossTraining (asRepo st) (WorkerId wid) (SkillId sid)
        putStrLn ("Removed cross-training goal: Worker " ++ show wid ++ " -> Skill " ++ show sid)

    WorkerAvoidPairing w1 w2 -> requireAdmin st $ do
        SW.addAvoidPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        putStrLn ("Workers " ++ show w1 ++ " and " ++ show w2 ++ " will avoid concurrent assignment")

    WorkerClearAvoidPairing w1 w2 -> requireAdmin st $ do
        SW.removeAvoidPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        putStrLn ("Cleared avoid-pairing: Workers " ++ show w1 ++ " and " ++ show w2)

    WorkerPreferPairing w1 w2 -> requireAdmin st $ do
        SW.addPreferPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        putStrLn ("Workers " ++ show w1 ++ " and " ++ show w2 ++ " prefer concurrent assignment")

    WorkerClearPreferPairing w1 w2 -> requireAdmin st $ do
        SW.removePreferPairing (asRepo st) (WorkerId w1) (WorkerId w2)
        putStrLn ("Cleared prefer-pairing: Workers " ++ show w1 ++ " and " ++ show w2)

    -- Pinned assignments
    PinAdd wid sid dayStr specStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                let spec = if all (`elem` "0123456789") specStr
                           then PinSlot (read specStr)
                           else PinShift specStr
                    pin = PinnedAssignment (WorkerId wid) (StationId sid) dow spec
                SW.addPin (asRepo st) pin
                putStrLn ("Pinned Worker " ++ show wid ++ " at Station " ++ show sid
                         ++ " on " ++ dayStr ++ " " ++ specStr)

    PinRemove wid sid dayStr specStr -> requireAdmin st $
        case parseDayOfWeek dayStr of
            Nothing -> putStrLn ("Unknown day: " ++ dayStr)
            Just dow -> do
                let spec = if all (`elem` "0123456789") specStr
                           then PinSlot (read specStr)
                           else PinShift specStr
                    pin = PinnedAssignment (WorkerId wid) (StationId sid) dow spec
                SW.removePin (asRepo st) pin
                putStrLn ("Unpinned Worker " ++ show wid ++ " at Station " ++ show sid
                         ++ " on " ++ dayStr ++ " " ++ specStr)

    PinList -> do
        pins <- SW.listPins (asRepo st)
        if null pins
            then putStrLn "  (no pinned assignments)"
            else mapM_ (\p ->
                putStrLn ("  Worker " ++ show (let WorkerId w = pinWorker p in w)
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

    -- Shifts (admin)
    ShiftCreate name sh eh -> requireAdmin st $ do
        repoSaveShift (asRepo st) (ShiftDef name sh eh)
        putStrLn ("Created shift: " ++ name ++ " (" ++ show sh ++ ":00-" ++ show eh ++ ":00)")

    ShiftList -> do
        shifts <- repoLoadShifts (asRepo st)
        if null shifts
            then putStrLn "  (no shifts configured — using defaults)"
            else mapM_ (\sd ->
                putStrLn ("  " ++ sdName sd ++ ": "
                         ++ show (sdStart sd) ++ ":00-" ++ show (sdEnd sd) ++ ":00")
                ) shifts

    ShiftDelete name -> requireAdmin st $ do
        repoDeleteShift (asRepo st) name
        putStrLn ("Deleted shift: " ++ name)

    -- Absence types (admin)
    AbsenceTypeCreate tid name lim -> requireAdmin st $ do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        let at = AbsenceType { atName = name, atYearlyLimit = lim }
            ctx' = ctx { acTypes = Map.insert (AbsenceTypeId tid) at (acTypes ctx) }
        repoSaveAbsenceCtx (asRepo st) ctx'
        putStrLn ("Created absence type: " ++ name)

    AbsenceTypeList -> do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        putStr (displayAbsenceTypes ctx)

    AbsenceSetAllowance wid tid days -> requireAdmin st $ do
        ctx <- repoLoadAbsenceCtx (asRepo st)
        let ctx' = ctx { acYearlyAllowance =
                Map.insert (WorkerId wid, AbsenceTypeId tid) days (acYearlyAllowance ctx) }
        repoSaveAbsenceCtx (asRepo st) ctx'
        putStrLn ("Set Worker " ++ show wid ++ " allowance for type " ++ show tid
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
        putStr (displayAbsences reqs)

    -- Absence request (worker or admin)
    CmdAbsenceRequest tid wid sd ed -> do
        let mStart = parseDay sd
            mEnd   = parseDay ed
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
        putStr (displayAbsences reqs)

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
        result <- register (asRepo st) name pass r (WorkerId nextWid)
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
        dat <- Export.gatherExport (asRepo st) (Just name)
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
            else mapM_ (\(ts, user, c) ->
                putStrLn ("  " ++ ts ++ "  " ++ user ++ ": " ++ c)
                ) entries

    CmdReplay -> requireAdmin st $ do
        entries <- repoGetAuditLog (asRepo st)
        if null entries
            then putStrLn "  (no audit entries to replay)"
            else replayCommands fastReplay st entries

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
                _ <- register (asRepo st) "admin" "admin" Admin (WorkerId 1)
                putStrLn "Created default admin user (admin/admin), Worker 1"
                replayCommands fastReplay st entries
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
        result <- changePassword (asRepo st) (userId (asUser st)) old new
        case result of
            Right () -> putStrLn "Password changed."
            Left WrongOldPassword -> putStrLn "Wrong old password."
            Left err -> putStrLn ("Error: " ++ show err)

    Unknown s -> putStrLn ("Unknown command: " ++ s ++ ". Type 'help' for available commands.")
    _ -> putStrLn "Command not handled."

requireAdmin :: AppState -> IO () -> IO ()
requireAdmin st action
    | userRole (asUser st) == Admin = action
    | otherwise = putStrLn "Permission denied. Admin required."

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
showPinSpec (PinShift sn) = sn ++ " shift"

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
            let cmd = parseCommand cmdStr
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

-- | Run demo mode: create admin, replay commands from a file with delay.
-- Called from Main when --demo flag is used.
runDemo :: Repository -> Int -> [String] -> IO ()
runDemo repo delayUs cmdLines = do
    -- Create default admin
    result <- register repo "admin" "admin" Admin (WorkerId 1)
    case result of
        Right _  -> putStrLn "Created default admin user (admin/admin)"
        Left err -> putStrLn ("Warning: " ++ show err)
    -- Load admin user for AppState
    mUser <- repoGetUserByName repo "admin"
    case mUser of
        Nothing -> putStrLn "ERROR: admin user not found after creation"
        Just adminUser -> do
            st <- mkAppState repo adminUser
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
    repoSavepoint (asRepo st) name
    writeIORef (asCheckpoints st) (name : stack)
    putStrLn ("Checkpoint created: " ++ name)

handleCheckpointCommit :: AppState -> IO ()
handleCheckpointCommit st = do
    stack <- readIORef (asCheckpoints st)
    case stack of
        [] -> putStrLn "No active checkpoint."
        (name : rest) -> do
            repoRelease (asRepo st) name
            writeIORef (asCheckpoints st) rest
            putStrLn ("Checkpoint committed: " ++ name)

handleCheckpointRollback :: AppState -> Maybe String -> IO ()
handleCheckpointRollback st mName = do
    stack <- readIORef (asCheckpoints st)
    case stack of
        [] -> putStrLn "No active checkpoint."
        (top : _) -> case mName of
            Nothing -> do
                repoRollbackTo (asRepo st) top
                putStrLn ("Rolled back to: " ++ top)
            Just target ->
                if target `elem` stack
                then do
                    -- Rollback to the named checkpoint, discard newer ones
                    repoRollbackTo (asRepo st) target
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
    , ("skill",    False, "skill list",                      "List all skills")
    , ("skill",    True,  "skill implication <a> <b>",       "Skill A implies skill B")
    , ("skill",    False, "skill info",                      "Show skill context")
    -- Station
    , ("station",  True,  "station add <id> <name>",         "Add a station")
    , ("station",  False, "station list",                    "List stations")
    , ("station",  True,  "station remove <id>",             "Remove a station")
    , ("station",  True,  "station set-hours <id> <start> <end>", "Set station operating hours")
    , ("station",  True,  "station close-day <id> <day>",    "Close station on day of week")
    , ("station",  True,  "station set-multi-hours <id> <start> <end>", "Set multi-station hours")
    , ("station",  True,  "station require-skill <sid> <skid>", "Require skill for station")
    -- Worker
    , ("worker",   True,  "worker grant-skill <wid> <sid>",  "Grant skill to worker")
    , ("worker",   True,  "worker revoke-skill <wid> <sid>", "Revoke skill from worker")
    , ("worker",   True,  "worker set-hours <wid> <hours>",  "Set max weekly hours")
    , ("worker",   True,  "worker set-overtime <wid> <on|off>", "Toggle overtime opt-in")
    , ("worker",   True,  "worker set-prefs <wid> <sid...>", "Set station preferences")
    , ("worker",   True,  "worker set-shift-pref <wid> <shift...>", "Set shift preferences")
    , ("worker",   True,  "worker set-weekend-only <wid> <on|off>", "Mark worker as weekend-only")
    , ("worker",   True,  "worker set-variety <wid> <on|off>", "Toggle variety preference")
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
    , ("absence",  True,  "absence-type create <id> <name> <on|off>", "Create absence type")
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
    -- Pin
    , ("pin",      True,  "pin <wid> <sid> <day> <hour|shift>", "Pin worker to station/slot")
    , ("pin",      True,  "unpin <wid> <sid> <day> <hour|shift>", "Remove pin")
    , ("pin",      True,  "pin list",                        "List pinned assignments")
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
    , ("context",  "Session context (use, view, clear)")
    , ("checkpoint", "Checkpoint, commit, and rollback")
    , ("export",   "JSON import and export")
    , ("audit",    "Audit trail and replay")
    , ("user",     "User account management")
    , ("general",  "Help, password, and exit")
    ]

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
        putStrLn ("  " ++ wName ++ " (Worker " ++ show widN ++ "):")
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
