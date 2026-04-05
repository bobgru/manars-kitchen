module CLI.Commands
    ( Command(..)
    , parseCommand
    ) where

-- | All commands available in the REPL.
data Command
    -- Schedule
    = ScheduleCreate String String    -- ^ name start-date (YYYY-MM-DD, week containing)
    | ScheduleView String             -- ^ name (tabular view)
    | ScheduleViewByWorker String
    | ScheduleViewByStation String
    | ScheduleList
    | ScheduleDelete String
    | ScheduleHours String             -- ^ worker hours summary
    | ScheduleDiagnose String         -- ^ diagnose unfilled positions
    | ScheduleClear String            -- ^ remove all assignments from named schedule
    -- Direct assignment
    | CmdAssign String Int Int String Int    -- ^ schedule worker station date hour
    | CmdUnassign String Int Int String Int  -- ^ schedule worker station date hour
    -- Skills / Stations (admin)
    | StationAdd Int String           -- ^ station-id name
    | StationList
    | StationRemove Int
    | StationSetHours Int Int Int   -- ^ station-id start-hour end-hour
    | StationCloseDay Int String   -- ^ station-id day-of-week
    | StationSetMultiHours Int Int Int  -- ^ station-id start-hour end-hour
    | StationRequireSkill Int Int    -- ^ station-id skill-id
    | SkillCreate Int String          -- ^ skill-id name
    | SkillList
    | SkillImplication Int Int       -- ^ skill-a skill-b (a implies b)
    | WorkerGrantSkill Int Int       -- ^ worker-id skill-id
    | WorkerRevokeSkill Int Int
    -- Workers (admin)
    | WorkerSetHours Int Int         -- ^ worker-id hours
    | WorkerSetOvertime Int Bool     -- ^ worker-id on/off
    | WorkerSetPrefs Int [Int]       -- ^ worker-id station-ids
    | WorkerSetVariety Int Bool
    | WorkerSetShiftPref Int [String]  -- ^ worker-id shift-names (morning/afternoon/evening)
    | WorkerSetWeekendOnly Int Bool   -- ^ worker-id on/off
    | WorkerInfo
    | SkillInfo
    -- Shifts (admin)
    | ShiftCreate String Int Int    -- ^ name start-hour end-hour
    | ShiftList
    | ShiftDelete String            -- ^ name
    -- Absences (admin)
    | AbsenceTypeCreate Int String Bool  -- ^ type-id name yearly-limit?
    | AbsenceTypeList
    | AbsenceSetAllowance Int Int Int    -- ^ worker-id type-id days
    | AbsenceApprove Int
    | AbsenceReject Int
    | AbsenceListPending
    -- Absences (worker)
    | CmdAbsenceRequest Int Int String String  -- ^ type-id worker-id start end (dates)
    | AbsenceListMine
    | VacationRemaining Int              -- ^ type-id
    -- Users (admin)
    | UserCreate String String String    -- ^ username password role
    | UserList
    | UserDelete Int
    -- Config
    | ConfigShow
    | ConfigSet String String       -- ^ key value
    | ConfigPreset String           -- ^ preset name
    | ConfigPresetList
    | ConfigReset
    -- Seniority
    | WorkerSetSeniority Int Int    -- ^ worker-id level
    -- Cross-training goals
    | WorkerSetCrossTraining Int Int    -- ^ worker-id skill-id
    | WorkerClearCrossTraining Int Int  -- ^ worker-id skill-id
    -- Pairing
    | WorkerAvoidPairing Int Int       -- ^ worker-id other-id
    | WorkerClearAvoidPairing Int Int
    | WorkerPreferPairing Int Int      -- ^ worker-id other-id
    | WorkerClearPreferPairing Int Int
    -- Pinned assignments
    | PinAdd Int Int String String   -- ^ worker-id station-id day hour-or-shift
    | PinRemove Int Int String String
    | PinList
    -- Import / Export
    | CmdExport String              -- ^ file path (all data)
    | CmdExportSchedule String String  -- ^ schedule-name file-path
    | CmdImport String              -- ^ file path
    -- Audit
    | CmdAuditLog                   -- ^ show audit trail
    | CmdReplay                     -- ^ replay audit log
    | CmdReplayFile String          -- ^ replay commands from file
    | CmdDemo                       -- ^ wipe DB, replay audit log from scratch
    -- Self
    | PasswordChange
    | Help
    | Quit
    | Unknown String
    deriving (Show)

parseCommand :: String -> Command
parseCommand input = case words input of
    ["schedule", "create", name, date] -> ScheduleCreate name date
    ["schedule", "create", name]       -> ScheduleCreate name "2026-04-06"
    ["schedule", "view", name]         -> ScheduleView name
    ["schedule", "view-by-worker", name]  -> ScheduleViewByWorker name
    ["schedule", "view-by-station", name] -> ScheduleViewByStation name
    ["schedule", "view"]              -> Unknown "schedule view <name> — name required"
    ["schedule", "list"]               -> ScheduleList
    ["schedule", "delete", name]       -> ScheduleDelete name
    ["schedule", "hours", name]         -> ScheduleHours name
    ["schedule", "diagnose", name]     -> ScheduleDiagnose name
    ["schedule", "clear", name]        -> ScheduleClear name

    ["assign", sched, wid, sid, date, hr]
        | all isDigit' [wid, sid, hr] -> CmdAssign sched (read wid) (read sid) date (read hr)
    ["unassign", sched, wid, sid, date, hr]
        | all isDigit' [wid, sid, hr] -> CmdUnassign sched (read wid) (read sid) date (read hr)

    ["station", "add", sid, name]
        | isDigit' sid -> StationAdd (read sid) name
    ["station", "list"]            -> StationList
    ["station", "remove", sid]
        | isDigit' sid -> StationRemove (read sid)
    ["station", "set-hours", sid, sh, eh]
        | all isDigit' [sid, sh, eh] -> StationSetHours (read sid) (read sh) (read eh)
    ["station", "close-day", sid, day]
        | isDigit' sid -> StationCloseDay (read sid) day
    ["station", "set-multi-hours", sid, sh, eh]
        | all isDigit' [sid, sh, eh] -> StationSetMultiHours (read sid) (read sh) (read eh)
    ["station", "require-skill", sid, skid]
        | all isDigit' [sid, skid] -> StationRequireSkill (read sid) (read skid)

    ["skill", "create", sid, name]
        | isDigit' sid -> SkillCreate (read sid) name
    ["skill", "list"]              -> SkillList
    ["skill", "implication", a, b]
        | all isDigit' [a, b] -> SkillImplication (read a) (read b)
    ["skill", "info"]              -> SkillInfo

    ["worker", "grant-skill", wid, sid]
        | all isDigit' [wid, sid] -> WorkerGrantSkill (read wid) (read sid)
    ["worker", "revoke-skill", wid, sid]
        | all isDigit' [wid, sid] -> WorkerRevokeSkill (read wid) (read sid)
    ["worker", "set-hours", wid, h]
        | all isDigit' [wid, h] -> WorkerSetHours (read wid) (read h)
    ["worker", "set-overtime", wid, b]
        | isDigit' wid -> WorkerSetOvertime (read wid) (parseBool b)
    ["worker", "set-prefs", wid] -> WorkerSetPrefs (read wid) []
    ("worker" : "set-prefs" : wid : sids)
        | all isDigit' (wid : sids) -> WorkerSetPrefs (read wid) (map read sids)
    ["worker", "set-variety", wid, b]
        | isDigit' wid -> WorkerSetVariety (read wid) (parseBool b)
    ("worker" : "set-shift-pref" : wid : names)
        | isDigit' wid -> WorkerSetShiftPref (read wid) names
    ["worker", "set-weekend-only", wid, b]
        | isDigit' wid -> WorkerSetWeekendOnly (read wid) (parseBool b)
    ["worker", "info"]             -> WorkerInfo

    ["shift", "create", name, sh, eh]
        | all isDigit' [sh, eh] -> ShiftCreate name (read sh) (read eh)
    ["shift", "list"]          -> ShiftList
    ["shift", "delete", name]  -> ShiftDelete name

    ["absence-type", "create", tid, name, lim]
        | isDigit' tid -> AbsenceTypeCreate (read tid) name (parseBool lim)
    ["absence-type", "list"]       -> AbsenceTypeList
    ["absence", "set-allowance", wid, tid, days]
        | all isDigit' [wid, tid, days] -> AbsenceSetAllowance (read wid) (read tid) (read days)
    ["absence", "approve", aid]
        | isDigit' aid -> AbsenceApprove (read aid)
    ["absence", "reject", aid]
        | isDigit' aid -> AbsenceReject (read aid)
    ["absence", "list-pending"]    -> AbsenceListPending
    ["absence", "request", tid, wid, sd, ed]
        | all isDigit' [tid, wid] -> CmdAbsenceRequest (read tid) (read wid) sd ed
    ["absence", "list"]            -> AbsenceListMine
    ["vacation", "remaining", tid]
        | isDigit' tid -> VacationRemaining (read tid)

    ["user", "create", name, pass, role] -> UserCreate name pass role
    ["user", "list"]               -> UserList
    ["user", "delete", uid]
        | isDigit' uid -> UserDelete (read uid)

    ["config", "show"]               -> ConfigShow
    ["config", "set", key, val]      -> ConfigSet key val
    ["config", "preset", name]       -> ConfigPreset name
    ["config", "preset-list"]        -> ConfigPresetList
    ["config", "reset"]              -> ConfigReset

    ["worker", "set-seniority", wid, lvl]
        | all isDigit' [wid, lvl] -> WorkerSetSeniority (read wid) (read lvl)
    ["worker", "set-cross-training", wid, sid]
        | all isDigit' [wid, sid] -> WorkerSetCrossTraining (read wid) (read sid)
    ["worker", "clear-cross-training", wid, sid]
        | all isDigit' [wid, sid] -> WorkerClearCrossTraining (read wid) (read sid)
    ["worker", "avoid-pairing", w1, w2]
        | all isDigit' [w1, w2] -> WorkerAvoidPairing (read w1) (read w2)
    ["worker", "clear-avoid-pairing", w1, w2]
        | all isDigit' [w1, w2] -> WorkerClearAvoidPairing (read w1) (read w2)
    ["worker", "prefer-pairing", w1, w2]
        | all isDigit' [w1, w2] -> WorkerPreferPairing (read w1) (read w2)
    ["worker", "clear-prefer-pairing", w1, w2]
        | all isDigit' [w1, w2] -> WorkerClearPreferPairing (read w1) (read w2)

    ["pin", wid, sid, day, spec]
        | all isDigit' [wid, sid] -> PinAdd (read wid) (read sid) day spec
    ["unpin", wid, sid, day, spec]
        | all isDigit' [wid, sid] -> PinRemove (read wid) (read sid) day spec
    ["pin", "list"]                  -> PinList

    ["export", name, file]          -> CmdExportSchedule name file
    ["export", file]                 -> CmdExport file
    ["import", file]                 -> CmdImport file

    ["audit"]                        -> CmdAuditLog
    ["replay"]                       -> CmdReplay
    ["replay", file]                 -> CmdReplayFile file
    ["demo"]                         -> CmdDemo

    ["password", "change"]         -> PasswordChange
    ["help"]                       -> Help
    ["quit"]                       -> Quit
    ["exit"]                       -> Quit
    _                              -> Unknown input

isDigit' :: String -> Bool
isDigit' [] = False
isDigit' s  = all (`elem` "0123456789") s

parseBool :: String -> Bool
parseBool "on"   = True
parseBool "yes"  = True
parseBool "true" = True
parseBool _      = False
