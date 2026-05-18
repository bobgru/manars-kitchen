module CLI.Commands
    ( Command(..)
    , parseCommand
    , shellWords
    , shellQuote
    ) where

import Data.Text (Text, pack)
import Domain.Types (SkillId(..))
import Utils (shellWords, shellQuote)

-- | All commands available in the REPL.
data Command
    -- Schedule
    = ScheduleCreate String String    -- ^ name start-date (YYYY-MM-DD, week containing)
    | ScheduleView String             -- ^ name (tabular view)
    | ScheduleViewByWorker String
    | ScheduleViewByStation String
    | ScheduleViewCompact String     -- ^ name (compact tabular view)
    | ScheduleList
    | ScheduleDelete String
    | ScheduleHours String             -- ^ worker hours summary
    | ScheduleDiagnose String         -- ^ diagnose unfilled positions
    | ScheduleClear String            -- ^ remove all assignments from named schedule
    -- Direct assignment
    | CmdAssign String Int Int String Int    -- ^ schedule worker station date hour
    | CmdUnassign String Int Int String Int  -- ^ schedule worker station date hour
    -- Skills / Stations (admin)
    | StationCreate String Int Int    -- ^ name min-staff max-staff
    | StationList
    | StationDelete String            -- ^ name (safe delete)
    | StationForceDelete String       -- ^ name (remove refs + delete)
    | StationRename String String     -- ^ old-name new-name
    | StationView String              -- ^ name
    | StationSetHours String Int Int  -- ^ name start-hour end-hour
    | StationCloseDay String String   -- ^ name day-of-week
    | StationSetMultiHours String Int Int  -- ^ name start-hour end-hour
    | StationRequireSkill String SkillId    -- ^ name skill-id
    | StationRemoveRequiredSkill String SkillId -- ^ name skill-id
    | SkillCreate String                  -- ^ name
    | SkillRename SkillId String          -- ^ skill-id new-name
    | SkillDelete SkillId                 -- ^ skill-id (safe delete)
    | SkillForceDelete SkillId            -- ^ skill-id (remove refs + delete)
    | SkillView SkillId                  -- ^ skill-id (detailed view)
    | SkillList
    | SkillImplication SkillId SkillId       -- ^ skill-a skill-b (a implies b)
    | SkillRemoveImplication SkillId SkillId -- ^ skill-a skill-b (remove a implies b)
    | WorkerGrantSkill Int SkillId       -- ^ worker-id skill-id
    | WorkerRevokeSkill Int SkillId
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
    | AbsenceTypeCreate String Bool      -- ^ name yearly-limit?
    | AbsenceTypeList
    | AbsenceSetAllowance Int Int Int    -- ^ worker-id type-id days
    | AbsenceApprove Int
    | AbsenceReject Int
    | AbsenceListPending
    -- Absences (worker)
    | CmdAbsenceRequest Int Int Text Text       -- ^ type-id worker-id start end (dates)
    | AbsenceListMine
    | VacationRemaining Int              -- ^ type-id
    -- Users (admin)
    | UserCreate String String String Bool    -- ^ username password role no-worker?
    | UserList
    | UserRename String String                -- ^ old new username
    | UserDelete Int
    | UserForceDelete Int
    -- Worker entity (admin)
    | WorkerView String                       -- ^ name
    | WorkerDeactivate String
    | WorkerForceDeactivate String
    | WorkerActivate String
    | WorkerDelete String
    | WorkerForceDelete String
    -- Config
    | ConfigShow
    | ConfigSet String String       -- ^ key value
    | ConfigPreset String           -- ^ preset name
    | ConfigPresetList
    | ConfigReset
    | ConfigSetPayPeriod String String  -- ^ type anchor-date
    | ConfigShowPayPeriod
    -- Seniority
    | WorkerSetSeniority Int Int    -- ^ worker-id level
    -- Cross-training goals
    | WorkerSetCrossTraining Int SkillId    -- ^ worker-id skill-id
    | WorkerClearCrossTraining Int SkillId  -- ^ worker-id skill-id
    -- Employment status
    | WorkerSetStatus Int String       -- ^ worker-id salaried|full-time|part-time|per-diem
    | WorkerSetOvertimeModel Int String -- ^ worker-id eligible|manual-only|exempt
    | WorkerSetPayTracking Int String   -- ^ worker-id standard|exempt
    | WorkerSetTemp Int Bool            -- ^ worker-id on|off
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
    | CmdReplay (Maybe String)      -- ^ wipe DB and replay (from file or audit log)
    -- Self
    | PasswordChange
    -- Checkpoint
    | CheckpointCreate (Maybe String) -- ^ optional name
    | CheckpointCommit
    | CheckpointRollback (Maybe String) -- ^ optional name
    | CheckpointList
    -- Calendar
    | CalendarView String String              -- ^ start-date end-date
    | CalendarViewByWorker String String
    | CalendarViewByStation String String
    | CalendarViewCompact String String
    | CalendarHours String String
    | CalendarDiagnose String String
    | CalendarDoCommit String String String (Maybe String) -- ^ schedule-name start end [note]
    | CalendarHistory
    | CalendarHistoryView String              -- ^ commit-id
    | CalendarUnfreeze String                 -- ^ single date
    | CalendarUnfreezeRange String String     -- ^ start end
    | CalendarFreezeStatus
    -- Draft
    | DraftCreate String String Bool    -- ^ start-date end-date force?
    | DraftThisMonth
    | DraftNextMonth
    | DraftList
    | DraftOpen String                  -- ^ draft-id
    | DraftView (Maybe String)          -- ^ optional draft-id
    | DraftViewCompact (Maybe String)   -- ^ optional draft-id
    | DraftGenerate (Maybe String)      -- ^ optional draft-id
    | DraftCommit (Maybe String) (Maybe String)  -- ^ optional draft-id, optional note
    | DraftDiscard (Maybe String)       -- ^ optional draft-id
    | DraftHours (Maybe String)         -- ^ optional draft-id
    | DraftDiagnose (Maybe String)      -- ^ optional draft-id
    -- What-if (hint session)
    | WhatIfCloseStation Int String Int       -- ^ station-id date hour
    | WhatIfPin Int Int String Int            -- ^ worker-id station-id date hour
    | WhatIfAddWorker String [String] (Maybe Int)  -- ^ name skills [hours]
    | WhatIfWaiveOvertime Int                 -- ^ worker-id
    | WhatIfGrantSkill Int SkillId                -- ^ worker-id skill-id
    | WhatIfOverridePrefs Int [Int]           -- ^ worker-id station-ids
    | WhatIfRevert
    | WhatIfRevertAll
    | WhatIfList
    | WhatIfApply
    | WhatIfRebase
    -- Context
    | CmdUse String String          -- ^ entity-type name-or-id
    | ContextView
    | ContextClear
    | ContextClearType String       -- ^ entity-type
    | Help
    | HelpGroup String
    | Quit
    | Unknown String
    deriving (Eq, Show)

parseCommand :: String -> Command
parseCommand input = case shellWords input of
    ["schedule", "create", name, date] -> ScheduleCreate name date
    ["schedule", "create", name]       -> ScheduleCreate name "2026-04-06"
    ["schedule", "view", name]         -> ScheduleView name
    ["schedule", "view-compact", name]    -> ScheduleViewCompact name
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

    ["station", "create", name] -> StationCreate name 1 1
    ["station", "create", name, mn, mx]
        | all isDigit' [mn, mx] -> StationCreate name (read mn) (read mx)
    ["station", "list"]            -> StationList
    ["station", "delete", name]    -> StationDelete name
    ["station", "force-delete", name] -> StationForceDelete name
    ["station", "rename", old, new] -> StationRename old new
    ["station", "view", name]      -> StationView name
    ["station", "set-hours", sid, sh, eh]
        | all isDigit' [sh, eh] -> StationSetHours sid (read sh) (read eh)
    ["station", "close-day", sid, day]
        -> StationCloseDay sid day
    ["station", "set-multi-hours", sid, sh, eh]
        | all isDigit' [sh, eh] -> StationSetMultiHours sid (read sh) (read eh)
    ["station", "require-skill", sid, skid]
        | isDigit' skid -> StationRequireSkill sid (SkillId (read skid))
    ["station", "remove-required-skill", sid, skid]
        | isDigit' skid -> StationRemoveRequiredSkill sid (SkillId (read skid))

    ["skill", "create", name] -> SkillCreate name
    ["skill", "rename", sid, name]
        | isDigit' sid -> SkillRename (SkillId (read sid)) name
    ["skill", "delete", sid]
        | isDigit' sid -> SkillDelete (SkillId (read sid))
    ["skill", "force-delete", sid]
        | isDigit' sid -> SkillForceDelete (SkillId (read sid))
    ["skill", "view", sid]
        | isDigit' sid -> SkillView (SkillId (read sid))
    ["skill", "list"]              -> SkillList
    ["skill", "implication", a, b]
        | all isDigit' [a, b] -> SkillImplication (SkillId (read a)) (SkillId (read b))
    ["skill", "remove-implication", a, b]
        | all isDigit' [a, b] -> SkillRemoveImplication (SkillId (read a)) (SkillId (read b))
    ["skill", "info"]              -> SkillInfo

    ["worker", "grant-skill", wid, sid]
        | all isDigit' [wid, sid] -> WorkerGrantSkill (read wid) (SkillId (read sid))
    ["worker", "revoke-skill", wid, sid]
        | all isDigit' [wid, sid] -> WorkerRevokeSkill (read wid) (SkillId (read sid))
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

    ["absence-type", "create", name, lim]
        -> AbsenceTypeCreate name (parseBool lim)
    ["absence-type", "list"]       -> AbsenceTypeList
    ["absence", "set-allowance", wid, tid, days]
        | all isDigit' [wid, tid, days] -> AbsenceSetAllowance (read wid) (read tid) (read days)
    ["absence", "approve", aid]
        | isDigit' aid -> AbsenceApprove (read aid)
    ["absence", "reject", aid]
        | isDigit' aid -> AbsenceReject (read aid)
    ["absence", "list-pending"]    -> AbsenceListPending
    ["absence", "request", tid, wid, sd, ed]
        | all isDigit' [tid, wid] -> CmdAbsenceRequest (read tid) (read wid) (pack sd) (pack ed)
    ["absence", "list"]            -> AbsenceListMine
    ["vacation", "remaining", tid]
        | isDigit' tid -> VacationRemaining (read tid)

    ["user", "create", name, pass, role] -> UserCreate name pass role False
    ["user", "create", name, pass, role, "--no-worker"] -> UserCreate name pass role True
    ["user", "list"]               -> UserList
    ["user", "rename", oldName, newName] -> UserRename oldName newName
    ["user", "delete", uid]
        | isDigit' uid -> UserDelete (read uid)
    ["user", "force-delete", uid]
        | isDigit' uid -> UserForceDelete (read uid)

    ["worker", "view", name]               -> WorkerView name
    ["worker", "deactivate", name]         -> WorkerDeactivate name
    ["worker", "force-deactivate", name]   -> WorkerForceDeactivate name
    ["worker", "activate", name]           -> WorkerActivate name
    ["worker", "delete", name]             -> WorkerDelete name
    ["worker", "force-delete", name]       -> WorkerForceDelete name

    ["config", "show"]               -> ConfigShow
    ["config", "set", key, val]      -> ConfigSet key val
    ["config", "preset", name]       -> ConfigPreset name
    ["config", "preset-list"]        -> ConfigPresetList
    ["config", "reset"]              -> ConfigReset
    ["config", "set-pay-period", typ, anchor] -> ConfigSetPayPeriod typ anchor
    ["config", "show-pay-period"]    -> ConfigShowPayPeriod

    ["worker", "set-status", wid, status]
        | isDigit' wid -> WorkerSetStatus (read wid) status
    ["worker", "set-overtime-model", wid, model]
        | isDigit' wid -> WorkerSetOvertimeModel (read wid) model
    ["worker", "set-pay-tracking", wid, tracking]
        | isDigit' wid -> WorkerSetPayTracking (read wid) tracking
    ["worker", "set-temp", wid, b]
        | isDigit' wid -> WorkerSetTemp (read wid) (parseBool b)
    ["worker", "set-seniority", wid, lvl]
        | all isDigit' [wid, lvl] -> WorkerSetSeniority (read wid) (read lvl)
    ["worker", "set-cross-training", wid, sid]
        | all isDigit' [wid, sid] -> WorkerSetCrossTraining (read wid) (SkillId (read sid))
    ["worker", "clear-cross-training", wid, sid]
        | all isDigit' [wid, sid] -> WorkerClearCrossTraining (read wid) (SkillId (read sid))
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
    ["replay"]                       -> CmdReplay Nothing
    ["replay", file]                 -> CmdReplay (Just file)

    ["checkpoint", "create"]        -> CheckpointCreate Nothing
    ["checkpoint", "create", name]  -> CheckpointCreate (Just name)
    ["checkpoint", "commit"]        -> CheckpointCommit
    ["checkpoint", "rollback"]      -> CheckpointRollback Nothing
    ["checkpoint", "rollback", name] -> CheckpointRollback (Just name)
    ["checkpoint", "list"]          -> CheckpointList

    ["draft", "create", s, e, "--force"]  -> DraftCreate s e True
    ["draft", "create", s, e]            -> DraftCreate s e False
    ["draft", "this-month"]              -> DraftThisMonth
    ["draft", "next-month"]              -> DraftNextMonth
    ["draft", "list"]                    -> DraftList
    ["draft", "open", did]
        | isDigit' did                   -> DraftOpen did
    ["draft", "view"]                    -> DraftView Nothing
    ["draft", "view", did]
        | isDigit' did                   -> DraftView (Just did)
    ["draft", "view-compact"]            -> DraftViewCompact Nothing
    ["draft", "view-compact", did]
        | isDigit' did                   -> DraftViewCompact (Just did)
    ["draft", "generate"]                -> DraftGenerate Nothing
    ["draft", "generate", did]
        | isDigit' did                   -> DraftGenerate (Just did)
    ["draft", "commit"]                  -> DraftCommit Nothing Nothing
    ["draft", "commit", did]
        | isDigit' did                   -> DraftCommit (Just did) Nothing
    ("draft" : "commit" : did : rest)
        | isDigit' did                   -> DraftCommit (Just did) (Just (unwords rest))
    ["draft", "discard"]                 -> DraftDiscard Nothing
    ["draft", "discard", did]
        | isDigit' did                   -> DraftDiscard (Just did)
    ["draft", "hours"]                   -> DraftHours Nothing
    ["draft", "hours", did]
        | isDigit' did                   -> DraftHours (Just did)
    ["draft", "diagnose"]                -> DraftDiagnose Nothing
    ["draft", "diagnose", did]
        | isDigit' did                   -> DraftDiagnose (Just did)

    -- What-if
    ["what-if", "close-station", sid, date, hr]
        | all isDigit' [sid, hr] -> WhatIfCloseStation (read sid) date (read hr)
    ["what-if", "pin", wid, sid, date, hr]
        | all isDigit' [wid, sid, hr] -> WhatIfPin (read wid) (read sid) date (read hr)
    ("what-if" : "add-worker" : rest)
        | length rest >= 2 -> parseAddWorker rest
    ["what-if", "waive-overtime", wid]
        | isDigit' wid -> WhatIfWaiveOvertime (read wid)
    ["what-if", "grant-skill", wid, sid]
        | all isDigit' [wid, sid] -> WhatIfGrantSkill (read wid) (SkillId (read sid))
    ("what-if" : "override-prefs" : wid : sids)
        | isDigit' wid, not (null sids), all isDigit' sids
            -> WhatIfOverridePrefs (read wid) (map read sids)
    ["what-if", "revert"]       -> WhatIfRevert
    ["what-if", "revert-all"]   -> WhatIfRevertAll
    ["what-if", "list"]         -> WhatIfList
    ["what-if", "apply"]        -> WhatIfApply
    ["what-if", "rebase"]       -> WhatIfRebase

    ["calendar", "view", s, e]          -> CalendarView s e
    ["calendar", "view-by-worker", s, e] -> CalendarViewByWorker s e
    ["calendar", "view-by-station", s, e] -> CalendarViewByStation s e
    ["calendar", "view-compact", s, e]   -> CalendarViewCompact s e
    ["calendar", "hours", s, e]          -> CalendarHours s e
    ["calendar", "diagnose", s, e]       -> CalendarDiagnose s e
    ["calendar", "commit", name, s, e]   -> CalendarDoCommit name s e Nothing
    ("calendar" : "commit" : name : s : e : rest)
        -> CalendarDoCommit name s e (Just (unwords rest))
    ["calendar", "history"]              -> CalendarHistory
    ["calendar", "history", cid]
        | isDigit' cid -> CalendarHistoryView cid
    ["calendar", "history", _]           -> Unknown "calendar history <commit-id> — id must be a number"
    ["calendar", "unfreeze", s, e]         -> CalendarUnfreezeRange s e
    ["calendar", "unfreeze", d]            -> CalendarUnfreeze d
    ["calendar", "freeze-status"]          -> CalendarFreezeStatus

    ["use", typ, ref]              -> CmdUse typ ref
    ["context", "view"]            -> ContextView
    ["context", "clear"]           -> ContextClear
    ["context", "clear", typ]      -> ContextClearType typ

    ["password", "change"]         -> PasswordChange
    ["help"]                       -> Help
    ["help", group]                -> HelpGroup group
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

-- | Parse "what-if add-worker <name> <skills...> [hours]"
-- If the last token is numeric, treat it as hours; rest are skill names.
parseAddWorker :: [String] -> Command
parseAddWorker [] = Unknown "what-if add-worker requires <name> <skills...>"
parseAddWorker [name] = Unknown ("what-if add-worker " ++ name ++ " requires at least one skill")
parseAddWorker (name : rest) =
    let lastTok  = last rest
        initToks = init rest
    in if isDigit' lastTok && not (null initToks)
       then WhatIfAddWorker name initToks (Just (read lastTok))
       else WhatIfAddWorker name rest Nothing
