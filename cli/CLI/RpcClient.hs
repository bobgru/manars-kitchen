{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module CLI.RpcClient
    ( RpcEnv(..)
    , mkRpcEnv
    , dispatchCommand
    ) where

import Data.Time (Day, fromGregorian, toGregorian, gregorianMonthLength)
import Data.Time.Clock (getCurrentTime, utctDay)
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Servant.API ((:<|>)(..))
import Servant.Client
    ( ClientM, ClientEnv, mkClientEnv, runClientM, client
    , parseBaseUrl, ClientError(..), responseStatusCode
    )
import Network.HTTP.Types.Status (statusCode)

import Auth.Types (User(..), Username(..), Role(..))
import Domain.Types (SkillId(..), Schedule(..))
import Domain.Skill (Skill(..))
import Domain.Shift (ShiftDef(..))
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment(..))
import Domain.Absence (AbsenceRequest)
import Domain.Scheduler (ScheduleResult)
import Domain.Worker (OvertimeModel(..), PayPeriodTracking(..))
import Domain.SchedulerConfig (presetNames)
import Repo.Types (DraftInfo(..), CalendarCommit(..), AuditEntry(..))
import CLI.Commands (Command(..))
import CLI.Display
import Server.Json
import Server.Rpc

-- -----------------------------------------------------------------
-- RPC environment
-- -----------------------------------------------------------------

data RpcEnv = RpcEnv
    { reClientEnv  :: !ClientEnv
    , reSessionId  :: !Int
    , reUserId     :: !Int
    , reUserRole   :: !Role
    }

mkRpcEnv :: String -> Int -> Int -> Role -> IO RpcEnv
mkRpcEnv serverUrl uid sid role = do
    mgr <- newManager defaultManagerSettings
    baseUrl <- parseBaseUrl serverUrl
    let env = mkClientEnv mgr baseUrl
    return (RpcEnv env sid uid role)

-- -----------------------------------------------------------------
-- Servant client bindings (derived from RpcAPI)
-- -----------------------------------------------------------------

cCreateSkill    :: CreateSkillReq -> ClientM RpcOk
_cDeleteSkill   :: RpcSkillId -> ClientM RpcOk
cRenameSkill    :: Int -> RenameSkillReq -> ClientM RpcOk
cListSkills     :: RpcEmpty -> ClientM [(SkillId, Skill)]
cCreateStation  :: CreateStationReq -> ClientM RpcOk
cDeleteStation  :: RpcStationId -> ClientM RpcOk
cSetStationHours :: RpcStationHours -> ClientM RpcOk
_cCloseStationDay :: SetStationClosureReq' -> ClientM RpcOk
cListStations   :: RpcEmpty -> ClientM [(Int, String)]
cCreateShift    :: CreateShiftReq -> ClientM RpcOk
cDeleteShift    :: RpcShiftName -> ClientM RpcOk
cListShifts     :: RpcEmpty -> ClientM [ShiftDef]
cSetWorkerHours :: RpcWorkerHours -> ClientM RpcOk
cSetWorkerOvertime :: RpcWorkerOvertime -> ClientM RpcOk
cSetWorkerPrefs :: RpcWorkerPrefs -> ClientM RpcOk
cSetWorkerVariety :: RpcWorkerVariety -> ClientM RpcOk
cSetWorkerShiftPrefs :: RpcWorkerShiftPrefs -> ClientM RpcOk
cSetWorkerWeekendOnly :: RpcWorkerWeekendOnly -> ClientM RpcOk
cSetWorkerSeniority :: RpcWorkerSeniority -> ClientM RpcOk
cAddCrossTraining :: RpcWorkerCrossTraining -> ClientM RpcOk
cSetEmploymentStatus :: RpcWorkerEmploymentStatus -> ClientM RpcOk
cSetOvertimeModel :: RpcWorkerOvertimeModel -> ClientM RpcOk
cSetPayTracking :: RpcWorkerPayTracking -> ClientM RpcOk
cSetTemp        :: RpcWorkerTemp -> ClientM RpcOk
cGrantSkill     :: RpcWorkerSkill -> ClientM RpcOk
cRevokeSkill    :: RpcWorkerSkill -> ClientM RpcOk
cAvoidPairing   :: RpcWorkerPairing -> ClientM RpcOk
cPreferPairing  :: RpcWorkerPairing -> ClientM RpcOk
_cAddPin        :: PinnedAssignment -> ClientM RpcOk
_cRemovePin     :: PinnedAssignment -> ClientM RpcOk
cListPins       :: RpcEmpty -> ClientM [PinnedAssignment]
cCreateDraft    :: CreateDraftReq -> ClientM DraftCreatedResp
cListDrafts     :: RpcEmpty -> ClientM [DraftInfo]
cViewDraft      :: RpcDraftId -> ClientM DraftInfo
cGenerateDraft  :: RpcDraftGenerate -> ClientM ScheduleResult
cCommitDraft    :: RpcDraftCommit -> ClientM RpcOk
cDiscardDraft   :: RpcDraftId -> ClientM RpcOk
cListSchedules  :: RpcEmpty -> ClientM [String]
cViewSchedule   :: RpcScheduleName -> ClientM Schedule
cDeleteSchedule :: RpcScheduleName -> ClientM RpcOk
cViewCalendar   :: RpcDateRange -> ClientM Schedule
cCalendarHistory :: RpcEmpty -> ClientM [CalendarCommit]
cUnfreeze       :: UnfreezeReq -> ClientM RpcOk
cFreezeStatus   :: RpcEmpty -> ClientM FreezeStatusResp
cShowConfig     :: RpcEmpty -> ClientM [(String, Double)]
cSetConfig      :: RpcConfigSet -> ClientM RpcOk
cApplyPreset    :: RpcPresetName -> ClientM RpcOk
cResetConfig    :: RpcEmpty -> ClientM RpcOk
cSetPayPeriod   :: SetPayPeriodReq -> ClientM RpcOk
cListAudit      :: RpcEmpty -> ClientM [AuditEntry]
cCreateCheckpoint :: CreateCheckpointReq -> ClientM RpcOk
cCommitCheckpoint :: RpcCheckpointName -> ClientM RpcOk
cRollbackCheckpoint :: RpcCheckpointName -> ClientM RpcOk
cExportAll      :: RpcEmpty -> ClientM ExportResp
_cImportData    :: ImportReq -> ClientM ImportResp
cCreateAbsenceType :: CreateAbsenceTypeReq -> ClientM RpcOk
_cDeleteAbsenceType :: RpcAbsenceTypeId -> ClientM RpcOk
cSetAllowance   :: RpcSetAllowance -> ClientM RpcOk
cRequestAbsence :: RequestAbsenceReq -> ClientM AbsenceCreatedResp
cApproveAbsence :: RpcAbsenceId -> ClientM RpcOk
cRejectAbsence  :: RpcAbsenceId -> ClientM RpcOk
cListPendingAbsences :: RpcEmpty -> ClientM [AbsenceRequest]
cCreateUser     :: CreateUserReq -> ClientM RpcOk
cListUsers      :: RpcEmpty -> ClientM [User]
_cDeleteUser    :: RpcUsername -> ClientM RpcOk
_cAddHint       :: AddHintReq -> ClientM [Hint]
_cRevertHint    :: HintSessionRef -> ClientM [Hint]
_cListHints     :: HintSessionRef -> ClientM [Hint]
_cApplyHints    :: HintSessionRef -> ClientM RpcOk
_cRebaseHints   :: HintSessionRef -> ClientM RebaseResultResp
_cCreateSession :: RpcSessionCreate -> ClientM RpcSessionResp
_cResumeSession :: RpcSessionCreate -> ClientM RpcSessionResp
_cExecute :: ExecuteReq -> ClientM String

cCreateSkill
    :<|> _cDeleteSkill
    :<|> cRenameSkill
    :<|> cListSkills
    :<|> cCreateStation
    :<|> cDeleteStation
    :<|> cSetStationHours
    :<|> _cCloseStationDay
    :<|> cListStations
    :<|> cCreateShift
    :<|> cDeleteShift
    :<|> cListShifts
    :<|> cSetWorkerHours
    :<|> cSetWorkerOvertime
    :<|> cSetWorkerPrefs
    :<|> cSetWorkerVariety
    :<|> cSetWorkerShiftPrefs
    :<|> cSetWorkerWeekendOnly
    :<|> cSetWorkerSeniority
    :<|> cAddCrossTraining
    :<|> cSetEmploymentStatus
    :<|> cSetOvertimeModel
    :<|> cSetPayTracking
    :<|> cSetTemp
    :<|> cGrantSkill
    :<|> cRevokeSkill
    :<|> cAvoidPairing
    :<|> cPreferPairing
    :<|> _cAddPin
    :<|> _cRemovePin
    :<|> cListPins
    :<|> cCreateDraft
    :<|> cListDrafts
    :<|> cViewDraft
    :<|> cGenerateDraft
    :<|> cCommitDraft
    :<|> cDiscardDraft
    :<|> cListSchedules
    :<|> cViewSchedule
    :<|> cDeleteSchedule
    :<|> cViewCalendar
    :<|> cCalendarHistory
    :<|> cUnfreeze
    :<|> cFreezeStatus
    :<|> cShowConfig
    :<|> cSetConfig
    :<|> cApplyPreset
    :<|> cResetConfig
    :<|> cSetPayPeriod
    :<|> cListAudit
    :<|> cCreateCheckpoint
    :<|> cCommitCheckpoint
    :<|> cRollbackCheckpoint
    :<|> cExportAll
    :<|> _cImportData
    :<|> cCreateAbsenceType
    :<|> _cDeleteAbsenceType
    :<|> cSetAllowance
    :<|> cRequestAbsence
    :<|> cApproveAbsence
    :<|> cRejectAbsence
    :<|> cListPendingAbsences
    :<|> cCreateUser
    :<|> cListUsers
    :<|> _cDeleteUser
    :<|> _cAddHint
    :<|> _cRevertHint
    :<|> _cListHints
    :<|> _cApplyHints
    :<|> _cRebaseHints
    :<|> _cCreateSession
    :<|> _cResumeSession
    :<|> _cExecute
    = client rpcApi

-- -----------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------

run :: RpcEnv -> ClientM a -> IO (Either String a)
run env action = do
    result <- runClientM action (reClientEnv env)
    case result of
        Right a -> return (Right a)
        Left (FailureResponse _ resp) ->
            return (Left ("Server error: " ++ show (statusCode (responseStatusCode resp))))
        Left (ConnectionError _) ->
            return (Left "Connection failed: is the server running?")
        Left err ->
            return (Left ("RPC error: " ++ show err))

runOk :: RpcEnv -> ClientM RpcOk -> String -> IO ()
runOk env action msg = do
    result <- run env action
    case result of
        Right _ -> putStrLn msg
        Left err -> putStrLn err

requireAdmin :: RpcEnv -> IO () -> IO ()
requireAdmin env action =
    if reUserRole env == Admin
        then action
        else putStrLn "Permission denied: admin only."

-- Parse a date string, returning Nothing on failure.
parseDay :: String -> Maybe Day
parseDay s = case break (== '-') s of
    (y, '-':rest) -> case break (== '-') rest of
        (m, '-':d) -> Just (fromGregorian (read y) (read m) (read d))
        _ -> Nothing
    _ -> Nothing

-- -----------------------------------------------------------------
-- Command dispatch
-- -----------------------------------------------------------------

dispatchCommand :: RpcEnv -> Command -> IO ()
dispatchCommand env cmd = case cmd of
    -- Schedule
    ScheduleList -> do
        result <- run env (cListSchedules RpcEmpty)
        case result of
            Right names -> if null names
                then putStrLn "  (no schedules)"
                else mapM_ (\n -> putStrLn ("  " ++ n)) names
            Left err -> putStrLn err

    ScheduleView name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displaySchedule s)
            Left err -> putStrLn err

    ScheduleViewByWorker name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displayScheduleByWorker s)
            Left err -> putStrLn err

    ScheduleViewByStation name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displayScheduleByStation s)
            Left err -> putStrLn err

    ScheduleViewCompact name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displaySchedule s)  -- simplified in remote mode
            Left err -> putStrLn err

    ScheduleDelete name -> requireAdmin env $
        runOk env (cDeleteSchedule (RpcScheduleName name))
            ("Deleted schedule: " ++ name)

    ScheduleHours name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displaySchedule s)  -- simplified in remote mode
            Left err -> putStrLn err

    ScheduleDiagnose name -> do
        result <- run env (cViewSchedule (RpcScheduleName name))
        case result of
            Right s -> putStr (displaySchedule s)  -- simplified in remote mode
            Left err -> putStrLn err

    ScheduleClear _name ->
        putStrLn "schedule clear is not supported in remote mode."

    ScheduleCreate _name _date ->
        putStrLn "schedule create is not supported in remote mode (use drafts)."

    -- Direct assignment
    CmdAssign {} ->
        putStrLn "Direct assignment is not supported in remote mode."
    CmdUnassign {} ->
        putStrLn "Direct unassignment is not supported in remote mode."

    -- Skills
    SkillCreate (SkillId sid) name -> requireAdmin env $
        runOk env (cCreateSkill (CreateSkillReq sid name "")) "Skill created."

    SkillRename (SkillId sid) name -> requireAdmin env $
        runOk env (cRenameSkill sid (RenameSkillReq name)) ("Renamed skill " ++ show sid ++ " to \"" ++ name ++ "\"")

    SkillDelete _ ->
        putStrLn "skill delete is not yet supported in remote mode."

    SkillForceDelete _ ->
        putStrLn "skill force-delete is not yet supported in remote mode."

    SkillList -> do
        result <- run env (cListSkills RpcEmpty)
        case result of
            Right skills -> mapM_ (\(SkillId i, sk) ->
                putStrLn ("  " ++ show i ++ ": " ++ skillName sk)) skills
            Left err -> putStrLn err

    SkillImplication _a _b ->
        putStrLn "Skill implication management is not yet supported via RPC."

    SkillRemoveImplication _a _b ->
        putStrLn "Skill implication management is not yet supported via RPC."

    WorkerGrantSkill wid (SkillId sid) -> requireAdmin env $
        runOk env (cGrantSkill (RpcWorkerSkill wid sid)) "Skill granted."

    WorkerRevokeSkill wid (SkillId sid) -> requireAdmin env $
        runOk env (cRevokeSkill (RpcWorkerSkill wid sid)) "Skill revoked."

    -- Stations
    StationAdd sid name -> requireAdmin env $
        runOk env (cCreateStation (CreateStationReq sid name)) "Station added."

    StationList -> do
        result <- run env (cListStations RpcEmpty)
        case result of
            Right stations -> mapM_ (\(i, n) ->
                putStrLn ("  " ++ show i ++ ": " ++ n)) stations
            Left err -> putStrLn err

    StationRemove sid -> requireAdmin env $
        runOk env (cDeleteStation (RpcStationId sid)) "Station removed."

    StationSetHours sid start end -> requireAdmin env $
        runOk env (cSetStationHours (RpcStationHours sid start end))
            "Station hours set."

    StationCloseDay _sid _dayStr ->
        putStrLn "station close-day via RPC requires date-based closure. Not yet mapped."

    StationSetMultiHours {} ->
        putStrLn "Multi-station hours not yet supported via RPC."

    StationRequireSkill {} ->
        putStrLn "Station skill requirements not yet supported via RPC."

    StationRemoveRequiredSkill {} ->
        putStrLn "Station remove-required-skill is not yet supported in remote mode."

    -- Shifts
    ShiftCreate name start end -> requireAdmin env $
        runOk env (cCreateShift (CreateShiftReq name start end)) "Shift created."

    ShiftList -> do
        result <- run env (cListShifts RpcEmpty)
        case result of
            Right shifts -> mapM_ (\sd ->
                putStrLn ("  " ++ sdName sd ++ " (" ++
                    show (sdStart sd) ++ "-" ++ show (sdEnd sd) ++ ")")) shifts
            Left err -> putStrLn err

    ShiftDelete name -> requireAdmin env $
        runOk env (cDeleteShift (RpcShiftName name)) "Shift deleted."

    -- Worker configuration
    WorkerSetHours wid hrs -> requireAdmin env $
        runOk env (cSetWorkerHours (RpcWorkerHours wid hrs)) "Worker hours set."

    WorkerSetOvertime wid optIn -> requireAdmin env $
        runOk env (cSetWorkerOvertime (RpcWorkerOvertime wid optIn)) "Overtime opt-in set."

    WorkerSetPrefs wid sids -> requireAdmin env $
        runOk env (cSetWorkerPrefs (RpcWorkerPrefs wid sids)) "Preferences set."

    WorkerSetVariety wid prefer -> requireAdmin env $
        runOk env (cSetWorkerVariety (RpcWorkerVariety wid prefer)) "Variety preference set."

    WorkerSetShiftPref wid shifts -> requireAdmin env $
        runOk env (cSetWorkerShiftPrefs (RpcWorkerShiftPrefs wid shifts)) "Shift preferences set."

    WorkerSetWeekendOnly wid val -> requireAdmin env $
        runOk env (cSetWorkerWeekendOnly (RpcWorkerWeekendOnly wid val)) "Weekend-only set."

    WorkerSetSeniority wid level -> requireAdmin env $
        runOk env (cSetWorkerSeniority (RpcWorkerSeniority wid level)) "Seniority set."

    WorkerSetCrossTraining wid (SkillId sid) -> requireAdmin env $
        runOk env (cAddCrossTraining (RpcWorkerCrossTraining wid sid)) "Cross-training added."

    WorkerClearCrossTraining {} ->
        putStrLn "Clear cross-training not yet supported via RPC."

    WorkerSetStatus wid status -> requireAdmin env $
        runOk env (cSetEmploymentStatus (RpcWorkerEmploymentStatus wid status))
            "Employment status set."

    WorkerSetOvertimeModel wid modelStr -> requireAdmin env $
        case parseOvertimeModel modelStr of
            Nothing -> putStrLn ("Unknown overtime model: " ++ modelStr)
            Just m  -> runOk env (cSetOvertimeModel (RpcWorkerOvertimeModel wid m))
                "Overtime model set."

    WorkerSetPayTracking wid trackStr -> requireAdmin env $
        case parsePayTracking trackStr of
            Nothing -> putStrLn ("Unknown pay tracking: " ++ trackStr)
            Just t  -> runOk env (cSetPayTracking (RpcWorkerPayTracking wid t))
                "Pay tracking set."

    WorkerSetTemp wid val -> requireAdmin env $
        runOk env (cSetTemp (RpcWorkerTemp wid val)) "Temp flag set."

    WorkerInfo ->
        putStrLn "worker info is not yet supported in remote mode."

    SkillView _ ->
        putStrLn "skill view is not yet supported in remote mode."

    SkillInfo ->
        putStrLn "skill info is not yet supported in remote mode."

    -- Pairing
    WorkerAvoidPairing wid oid -> requireAdmin env $
        runOk env (cAvoidPairing (RpcWorkerPairing wid oid)) "Avoid-pairing set."

    WorkerClearAvoidPairing {} ->
        putStrLn "Clear avoid-pairing not yet supported via RPC."

    WorkerPreferPairing wid oid -> requireAdmin env $
        runOk env (cPreferPairing (RpcWorkerPairing wid oid)) "Prefer-pairing set."

    WorkerClearPreferPairing {} ->
        putStrLn "Clear prefer-pairing not yet supported via RPC."

    -- Pins
    PinAdd {} ->
        putStrLn "Pin add is not yet supported via RPC (requires pin spec parsing)."

    PinRemove {} ->
        putStrLn "Pin remove is not yet supported via RPC."

    PinList -> do
        result <- run env (cListPins RpcEmpty)
        case result of
            Right pins -> mapM_ (putStrLn . showPin) pins
            Left err -> putStrLn err

    -- Drafts
    DraftCreate startStr endStr _force -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> do
            result <- run env (cCreateDraft (CreateDraftReq s e))
            case result of
                Right resp -> putStrLn ("Draft created: " ++ show (dcrId resp))
                Left err -> putStrLn err
        _ -> putStrLn "Invalid date format. Use YYYY-MM-DD."

    DraftThisMonth -> do
        today <- utctDay <$> getCurrentTime
        let (y, m, _) = toGregorian today
            start = fromGregorian y m 1
            end = fromGregorian y m (gregorianMonthLength y m)
        result <- run env (cCreateDraft (CreateDraftReq start end))
        case result of
            Right resp -> putStrLn ("Draft created for this month: " ++ show (dcrId resp))
            Left err -> putStrLn err

    DraftNextMonth -> do
        today <- utctDay <$> getCurrentTime
        let (y, m, _) = toGregorian today
            (y', m') = if m == 12 then (y + 1, 1) else (y, m + 1)
            start = fromGregorian y' m' 1
            end = fromGregorian y' m' (gregorianMonthLength y' m')
        result <- run env (cCreateDraft (CreateDraftReq start end))
        case result of
            Right resp -> putStrLn ("Draft created for next month: " ++ show (dcrId resp))
            Left err -> putStrLn err

    DraftList -> do
        result <- run env (cListDrafts RpcEmpty)
        case result of
            Right drafts -> if null drafts
                then putStrLn "  (no drafts)"
                else mapM_ (\d -> putStrLn ("  " ++ show (diId d) ++ ": " ++
                    show (diDateFrom d) ++ " to " ++ show (diDateTo d))) drafts
            Left err -> putStrLn err

    DraftOpen _did ->
        putStrLn "draft open is client-side state; not applicable in remote mode."

    DraftView mDid -> case mDid of
        Just didStr -> do
            result <- run env (cViewDraft (RpcDraftId (read didStr)))
            case result of
                Right d -> putStrLn ("Draft " ++ show (diId d) ++ ": " ++
                    show (diDateFrom d) ++ " to " ++ show (diDateTo d))
                Left err -> putStrLn err
        Nothing -> putStrLn "Specify a draft ID."

    DraftViewCompact mDid -> dispatchCommand env (DraftView mDid)

    DraftGenerate mDid -> case mDid of
        Just didStr -> do
            result <- run env (cGenerateDraft (RpcDraftGenerate (read didStr) []))
            case result of
                Right _r -> putStrLn "Draft generated."
                Left err -> putStrLn err
        Nothing -> putStrLn "Specify a draft ID."

    DraftCommit mDid mNote -> case mDid of
        Just didStr -> do
            let note = maybe "" id mNote
            result <- run env (cCommitDraft (RpcDraftCommit (read didStr) note))
            case result of
                Right _ -> putStrLn "Draft committed."
                Left err -> putStrLn err
        Nothing -> putStrLn "Specify a draft ID."

    DraftDiscard mDid -> case mDid of
        Just didStr -> do
            result <- run env (cDiscardDraft (RpcDraftId (read didStr)))
            case result of
                Right _ -> putStrLn "Draft discarded."
                Left err -> putStrLn err
        Nothing -> putStrLn "Specify a draft ID."

    DraftHours _mDid ->
        putStrLn "draft hours is not yet supported in remote mode."

    DraftDiagnose _mDid ->
        putStrLn "draft diagnose is not yet supported in remote mode."

    -- Calendar
    CalendarView startStr endStr -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> do
            result <- run env (cViewCalendar (RpcDateRange s e))
            case result of
                Right sched -> putStr (displaySchedule sched)
                Left err -> putStrLn err
        _ -> putStrLn "Invalid date format."

    CalendarViewByWorker startStr endStr -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> do
            result <- run env (cViewCalendar (RpcDateRange s e))
            case result of
                Right sched -> putStr (displayScheduleByWorker sched)
                Left err -> putStrLn err
        _ -> putStrLn "Invalid date format."

    CalendarViewByStation startStr endStr -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> do
            result <- run env (cViewCalendar (RpcDateRange s e))
            case result of
                Right sched -> putStr (displayScheduleByStation sched)
                Left err -> putStrLn err
        _ -> putStrLn "Invalid date format."

    CalendarViewCompact startStr endStr ->
        dispatchCommand env (CalendarView startStr endStr)

    CalendarHours startStr endStr -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> do
            result <- run env (cViewCalendar (RpcDateRange s e))
            case result of
                Right sched -> putStr (displaySchedule sched)
                Left err -> putStrLn err
        _ -> putStrLn "Invalid date format."

    CalendarDiagnose startStr endStr ->
        dispatchCommand env (CalendarView startStr endStr)

    CalendarDoCommit {} ->
        putStrLn "Calendar commit is not supported in remote mode (use drafts)."

    CalendarHistory -> do
        result <- run env (cCalendarHistory RpcEmpty)
        case result of
            Right commits -> mapM_ (\c ->
                putStrLn ("  " ++ show (ccId c) ++ ": " ++
                    ccCommittedAt c ++ " (" ++
                    show (ccDateFrom c) ++ " to " ++ show (ccDateTo c) ++ ") " ++
                    ccNote c)) commits
            Left err -> putStrLn err

    CalendarHistoryView _commitId ->
        putStrLn "Calendar history view is not yet supported in remote mode."

    CalendarUnfreeze dateStr -> case parseDay dateStr of
        Just d -> runOk env (cUnfreeze (UnfreezeReq d d)) "Date unfrozen."
        Nothing -> putStrLn "Invalid date format."

    CalendarUnfreezeRange startStr endStr -> case (parseDay startStr, parseDay endStr) of
        (Just s, Just e) -> runOk env (cUnfreeze (UnfreezeReq s e)) "Range unfrozen."
        _ -> putStrLn "Invalid date format."

    CalendarFreezeStatus -> do
        result <- run env (cFreezeStatus RpcEmpty)
        case result of
            Right resp -> putStrLn ("Freeze line: " ++ show (fsFreezeLine resp))
            Left err -> putStrLn err

    -- Config
    ConfigShow -> do
        result <- run env (cShowConfig RpcEmpty)
        case result of
            Right params -> mapM_ (\(k, v) ->
                putStrLn ("  " ++ k ++ " = " ++ show v)) params
            Left err -> putStrLn err

    ConfigSet key valStr -> requireAdmin env $ do
        case reads valStr of
            [(v, "")] -> runOk env (cSetConfig (RpcConfigSet key v))
                ("Set " ++ key ++ " = " ++ show (v :: Double))
            _ -> putStrLn "Invalid value. Expected a number."

    ConfigPreset name -> requireAdmin env $
        runOk env (cApplyPreset (RpcPresetName name)) ("Applied preset: " ++ name)

    ConfigPresetList ->
        mapM_ (\n -> putStrLn ("  " ++ n)) presetNames

    ConfigReset -> requireAdmin env $
        runOk env (cResetConfig RpcEmpty) "Config reset to defaults."

    ConfigSetPayPeriod typeStr dateStr -> requireAdmin env $ case parseDay dateStr of
        Just d -> runOk env (cSetPayPeriod (SetPayPeriodReq typeStr d))
            "Pay period configured."
        Nothing -> putStrLn "Invalid date format."

    ConfigShowPayPeriod ->
        putStrLn "Pay period display is not yet supported in remote mode."

    -- Absence types
    AbsenceTypeCreate tid name counts -> requireAdmin env $
        runOk env (cCreateAbsenceType (CreateAbsenceTypeReq tid name counts))
            "Absence type created."

    AbsenceTypeList ->
        putStrLn "Absence type list is not yet available via RPC."

    AbsenceSetAllowance wid tid days -> requireAdmin env $
        runOk env (cSetAllowance (RpcSetAllowance tid wid days))
            "Allowance set."

    AbsenceApprove aid -> requireAdmin env $
        runOk env (cApproveAbsence (RpcAbsenceId aid)) "Absence approved."

    AbsenceReject aid -> requireAdmin env $
        runOk env (cRejectAbsence (RpcAbsenceId aid)) "Absence rejected."

    AbsenceListPending -> do
        result <- run env (cListPendingAbsences RpcEmpty)
        case result of
            Right reqs -> if null reqs
                then putStrLn "  (no pending absences)"
                else mapM_ (putStrLn . show) reqs
            Left err -> putStrLn err

    CmdAbsenceRequest tid wid startStr endStr ->
        case (parseDay startStr, parseDay endStr) of
            (Just s, Just e) -> do
                result <- run env (cRequestAbsence (RequestAbsenceReq wid tid s e))
                case result of
                    Right resp -> putStrLn ("Absence requested (id: " ++ show (acrId resp) ++ ")")
                    Left err -> putStrLn err
            _ -> putStrLn "Invalid date format."

    AbsenceListMine ->
        putStrLn "Absence list (mine) is not yet supported in remote mode."

    VacationRemaining _tid ->
        putStrLn "Vacation remaining is not yet supported in remote mode."

    -- Users
    UserCreate username password roleStr -> requireAdmin env $ do
        let role = case roleStr of
                "admin" -> Admin
                _       -> Normal
        runOk env (cCreateUser (CreateUserReq username password role 0))
            ("User created: " ++ username)

    UserList -> do
        result <- run env (cListUsers RpcEmpty)
        case result of
            Right users -> mapM_ (\u ->
                let Username n = userName u
                    r = if userRole u == Admin then "admin" else "normal"
                in putStrLn ("  " ++ n ++ " (" ++ r ++ ")")) users
            Left err -> putStrLn err

    UserDelete _uid ->
        putStrLn ("User delete by ID is not yet mapped to RPC (RPC uses username).")

    -- Audit
    CmdAuditLog -> do
        result <- run env (cListAudit RpcEmpty)
        case result of
            Right entries -> mapM_ (\e ->
                putStrLn (aeTimestamp e ++ " " ++ aeUsername e ++ ": " ++
                    maybe "(no command)" id (aeCommand e))) entries
            Left err -> putStrLn err

    CmdReplay ->
        putStrLn "Replay is not supported in remote mode."

    CmdReplayFile _ ->
        putStrLn "Replay from file is not supported in remote mode."

    CmdDemo ->
        putStrLn "Demo is not supported in remote mode."

    -- Import / Export
    CmdExport _path -> do
        result <- run env (cExportAll RpcEmpty)
        case result of
            Right _resp -> putStrLn "Export data received."
            Left err -> putStrLn err

    CmdExportSchedule {} ->
        putStrLn "Export schedule is not yet supported in remote mode."

    CmdImport _path ->
        putStrLn "Import in remote mode is not yet supported."

    -- Checkpoints
    CheckpointCreate mName -> requireAdmin env $ do
        let name = maybe "auto" id mName
        runOk env (cCreateCheckpoint (CreateCheckpointReq name)) ("Checkpoint created: " ++ name)

    CheckpointCommit -> requireAdmin env $
        runOk env (cCommitCheckpoint (RpcCheckpointName "auto")) "Checkpoint committed."

    CheckpointRollback mName -> requireAdmin env $ do
        let name = maybe "auto" id mName
        runOk env (cRollbackCheckpoint (RpcCheckpointName name)) ("Rolled back to: " ++ name)

    CheckpointList ->
        putStrLn "Checkpoint list is not yet supported in remote mode."

    -- Self
    PasswordChange ->
        putStrLn "Password change runs locally before entering remote mode."

    -- What-if (hint sessions)
    WhatIfCloseStation {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfPin {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfAddWorker {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfWaiveOvertime {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfGrantSkill {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfOverridePrefs {} ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfRevert ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfRevertAll ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfList ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfApply ->
        putStrLn "What-if commands are not yet supported in remote mode."

    WhatIfRebase ->
        putStrLn "What-if commands are not yet supported in remote mode."

    -- Context (client-side)
    CmdUse {} ->
        putStrLn "Context commands are client-side only."

    ContextView ->
        putStrLn "Context commands are client-side only."

    ContextClear ->
        putStrLn "Context commands are client-side only."

    ContextClearType {} ->
        putStrLn "Context commands are client-side only."

    -- Help / quit
    Help -> putStrLn "Help is available in local mode only."
    HelpGroup _ -> putStrLn "Help is available in local mode only."
    Quit -> putStrLn "Goodbye."
    Unknown s -> putStrLn ("Unknown command: " ++ s)

-- -----------------------------------------------------------------
-- Local helpers
-- -----------------------------------------------------------------

showPin :: PinnedAssignment -> String
showPin p = "  worker " ++ show (pinWorker p) ++ " -> station " ++
    show (pinStation p)

parseOvertimeModel :: String -> Maybe OvertimeModel
parseOvertimeModel "eligible"    = Just OTEligible
parseOvertimeModel "manual-only" = Just OTManualOnly
parseOvertimeModel "exempt"      = Just OTExempt
parseOvertimeModel _             = Nothing

parsePayTracking :: String -> Maybe PayPeriodTracking
parsePayTracking "standard" = Just PPStandard
parsePayTracking "exempt"   = Just PPExempt
parsePayTracking _          = Nothing
