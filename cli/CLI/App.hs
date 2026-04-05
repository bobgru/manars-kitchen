module CLI.App
    ( AppState(..)
    , runRepl
    , runDemo
    ) where

import System.IO (hFlush, stdout, hSetEcho, stdin)
import Control.Concurrent (threadDelay)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.ByteString.Lazy as BL
import Data.Time (Day, DayOfWeek(..), TimeOfDay(..), parseTimeM, defaultTimeLocale)

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
import Repo.Types (Repository(..))
import Service.Auth (AuthError(..), register, changePassword)
import qualified Service.Worker as SW
import qualified Service.Absence as SA
import qualified Service.Config as SC
import qualified Service.Optimize as Opt
import qualified Export.JSON as Export
import Domain.Optimizer (OptProgress(..), OptPhase(..))
import CLI.Commands (Command(..), parseCommand)
import CLI.Display

data AppState = AppState
    { asRepo :: !Repository
    , asUser :: !User
    }

runRepl :: AppState -> IO ()
runRepl st = do
    let Username uname = userName (asUser st)
        role = if userRole (asUser st) == Admin then "admin" else "user"
    putStr (uname ++ " [" ++ role ++ "]> ")
    hFlush stdout
    line <- getLine
    case parseCommand line of
        Quit -> putStrLn "Goodbye."
        Help -> printHelp (userRole (asUser st)) >> runRepl st
        cmd  -> do
            when (isMutating cmd) $
                repoLogCommand (asRepo st) uname line
            handleCommand st cmd
            runRepl st

-- | Commands that modify state and should be logged.
isMutating :: Command -> Bool
isMutating cmd = case cmd of
    ScheduleList        -> False
    ScheduleView _      -> False
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
    Quit                -> False
    Unknown _           -> False
    ConfigShow            -> False
    ConfigPresetList      -> False
    PinList               -> False
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
  where
    toLower c = if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c

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
            let st = AppState repo adminUser
                entries = [("", "", c) | c <- cmdLines]
            let opts = ReplayOpts delayUs (delayUs > 0)
            replayCommands opts st entries

printHelp :: Role -> IO ()
printHelp role = do
    putStrLn "Available commands:"
    putStrLn ""
    putStrLn "  schedule list                     List saved schedules"
    putStrLn "  schedule view <name>              View a schedule (table)"
    putStrLn "  schedule view-by-worker <name>    View schedule grouped by worker"
    putStrLn "  schedule view-by-station <name>   View schedule grouped by station"
    putStrLn "  schedule hours <name>              Worker hours summary"
    putStrLn "  schedule diagnose <name>          Diagnose unfilled positions"
    putStrLn ""
    putStrLn "  absence request <type-id> <worker-id> <start> <end>"
    putStrLn "                                    Request an absence (dates: YYYY-MM-DD)"
    putStrLn "  absence list                      List your absences"
    putStrLn "  vacation remaining <type-id>      Check remaining vacation days"
    putStrLn ""
    putStrLn "  password change                   Change your password"
    putStrLn "  help                              Show this help"
    putStrLn "  quit                              Exit"
    when (role == Admin) $ do
        putStrLn ""
        putStrLn "Admin commands:"
        putStrLn "  skill create <id> <name>           Create a skill"
        putStrLn "  skill list                         List all skills"
        putStrLn "  skill implication <a> <b>         Skill A implies skill B"
        putStrLn "  skill info                        Show skill context"
        putStrLn "  station add <id> <name>             Add a station"
        putStrLn "  station list                      List stations"
        putStrLn "  station remove <id>               Remove a station"
        putStrLn "  station set-hours <id> <start> <end>   Set station operating hours"
        putStrLn "  station close-day <id> <day>         Close station on day of week"
        putStrLn "  station set-multi-hours <id> <start> <end>  Set multi-station hours"
        putStrLn "  station require-skill <station-id> <skill-id>"
        putStrLn "  shift create <name> <start> <end>   Create a shift (hours)"
        putStrLn "  shift list                          List configured shifts"
        putStrLn "  shift delete <name>                 Delete a shift"
        putStrLn "  worker grant-skill <wid> <sid>    Grant skill to worker"
        putStrLn "  worker revoke-skill <wid> <sid>   Revoke skill from worker"
        putStrLn "  worker set-hours <wid> <hours>    Set max weekly hours"
        putStrLn "  worker set-overtime <wid> <on|off>"
        putStrLn "  worker set-prefs <wid> <sid...>   Set station preferences"
        putStrLn "  worker set-shift-pref <wid> <shift...>  Set shift prefs (morning/afternoon/evening)"
        putStrLn "  worker set-weekend-only <wid> <on|off>  Mark worker as weekend-only"
        putStrLn "  worker set-variety <wid> <on|off>"
        putStrLn "  worker set-seniority <wid> <level>  Set seniority level"
        putStrLn "  worker set-cross-training <wid> <sid>  Add cross-training goal"
        putStrLn "  worker clear-cross-training <wid> <sid>  Remove cross-training goal"
        putStrLn "  worker avoid-pairing <wid1> <wid2>  Prevent concurrent scheduling"
        putStrLn "  worker clear-avoid-pairing <wid1> <wid2>"
        putStrLn "  worker prefer-pairing <wid1> <wid2> Prefer concurrent scheduling"
        putStrLn "  worker clear-prefer-pairing <wid1> <wid2>"
        putStrLn "  worker info                       Show worker context"
        putStrLn "  pin <wid> <sid> <day> <hour|shift>  Pin worker to station/slot"
        putStrLn "  unpin <wid> <sid> <day> <hour|shift>  Remove pin"
        putStrLn "  pin list                          List pinned assignments"
        putStrLn "  config show                       Show scheduler config"
        putStrLn "  config set <key> <value>          Set a config parameter"
        putStrLn "  config preset <name>              Apply a named preset"
        putStrLn "  config preset-list                List available presets"
        putStrLn "  config reset                      Reset config to defaults"
        putStrLn "  absence-type create <id> <name> <yearly-limit:on|off>"
        putStrLn "  absence-type list                 List absence types"
        putStrLn "  absence set-allowance <wid> <tid> <days>"
        putStrLn "  absence approve <id>              Approve absence request"
        putStrLn "  absence reject <id>               Reject absence request"
        putStrLn "  absence list-pending              List pending requests"
        putStrLn "  schedule create <name> <date>     Create schedule (week of date)"
        putStrLn "  schedule delete <name>            Delete a schedule"
        putStrLn "  schedule clear <name>             Clear all assignments"
        putStrLn "  assign <sched> <wid> <sid> <date> <hour>"
        putStrLn "                                    Assign worker to station/slot"
        putStrLn "  unassign <sched> <wid> <sid> <date> <hour>"
        putStrLn "                                    Remove assignment"
        putStrLn "  user create <name> <pass> <role>  Create a user"
        putStrLn "  user list                         List all users"
        putStrLn "  user delete <id>                  Delete a user"
        putStrLn "  export <file>                     Export all data to JSON"
        putStrLn "  export <schedule> <file>          Export one schedule to JSON"
        putStrLn "  import <file>                     Import data from JSON"
        putStrLn "  audit                             Show audit trail"
        putStrLn "  replay                            Replay audit log"
        putStrLn "  replay <file>                     Replay commands from file"
        putStrLn "  demo                              Wipe DB and replay audit log"

when :: Bool -> IO () -> IO ()
when True  action = action
when False _      = return ()

-- | Show a Double with 1 decimal place.
showFFloat1 :: Double -> String
showFFloat1 x = show (fromIntegral (round (x * 10) :: Integer) / 10.0 :: Double)
