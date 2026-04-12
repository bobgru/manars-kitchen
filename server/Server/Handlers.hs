module Server.Handlers
    ( server
    , fullServer
    ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day)
import Servant

import Auth.Types (User(..))
import Domain.Types (WorkerId(..), StationId(..), AbsenceId(..), AbsenceTypeId(..), SkillId(..), Schedule)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef(..))
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest, AbsenceType(..), AbsenceContext(..))
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment)
import Domain.PayPeriod (parsePayPeriodType, PayPeriodConfig(..))
import Repo.Types (Repository(..), DraftInfo, CalendarCommit, AuditEntry(..), SessionId(..), HintSessionRecord(..))
import qualified Service.Worker as SW
import qualified Service.Schedule as SS
import qualified Service.Draft as SD
import qualified Service.Calendar as SC
import qualified Service.Absence as SA
import qualified Service.Config as SCfg
import qualified Service.Auth as SAuth
import qualified Service.FreezeLine as SF
import qualified Service.HintRebase as SHR
import qualified Export.JSON as Exp
import Server.Api (API, FullAPI)
import Server.Json
import Server.Error
import Server.Rpc (rpcServer)

server :: Repository -> Server API
server repo =
    -- Original endpoints
         handleListSkills repo
    :<|> handleListStations repo
    :<|> handleListShifts repo
    :<|> handleListSchedules repo
    :<|> handleGetSchedule repo
    :<|> handleDeleteSchedule repo
    :<|> handleListDrafts repo
    :<|> handleCreateDraft repo
    :<|> handleGetDraft repo
    :<|> handleGenerateDraft repo
    :<|> handleCommitDraft repo
    :<|> handleDiscardDraft repo
    :<|> handleGetCalendar repo
    :<|> handleListCalendarHistory repo
    :<|> handleGetCalendarCommit repo
    :<|> handleListPendingAbsences repo
    :<|> handleRequestAbsence repo
    :<|> handleApproveAbsence repo
    :<|> handleRejectAbsence repo
    :<|> handleGetConfig repo
    -- Skill CRUD
    :<|> handleCreateSkill repo
    :<|> handleDeleteSkill repo
    -- Station CRUD
    :<|> handleCreateStation repo
    :<|> handleDeleteStation repo
    :<|> handleSetStationHours repo
    :<|> handleSetStationClosure repo
    -- Shift CRUD
    :<|> handleCreateShift repo
    :<|> handleDeleteShift repo
    -- Worker configuration
    :<|> handleSetWorkerHours repo
    :<|> handleSetWorkerOvertime repo
    :<|> handleSetWorkerPrefs repo
    :<|> handleSetWorkerVariety repo
    :<|> handleSetWorkerShiftPrefs repo
    :<|> handleSetWorkerWeekendOnly repo
    :<|> handleSetWorkerSeniority repo
    :<|> handleSetWorkerCrossTraining repo
    :<|> handleSetWorkerEmploymentStatus repo
    :<|> handleSetWorkerOvertimeModel repo
    :<|> handleSetWorkerPayTracking repo
    :<|> handleSetWorkerTemp repo
    -- Worker skill grant/revoke
    :<|> handleGrantWorkerSkill repo
    :<|> handleRevokeWorkerSkill repo
    -- Worker pairing
    :<|> handleAvoidPairing repo
    :<|> handlePreferPairing repo
    -- Pins
    :<|> handleListPins repo
    :<|> handleAddPin repo
    :<|> handleRemovePin repo
    -- Calendar mutations
    :<|> handleUnfreeze
    :<|> handleFreezeStatus
    -- Config writes
    :<|> handleSetConfig repo
    :<|> handleApplyPreset repo
    :<|> handleResetConfig repo
    :<|> handleSetPayPeriod repo
    -- Audit
    :<|> handleGetAuditLog repo
    -- Checkpoints
    :<|> handleCreateCheckpoint repo
    :<|> handleCommitCheckpoint repo
    :<|> handleRollbackCheckpoint repo
    -- Import/Export
    :<|> handleExport repo
    :<|> handleImport repo
    -- Absence type management
    :<|> handleCreateAbsenceType repo
    :<|> handleDeleteAbsenceType repo
    :<|> handleSetAbsenceAllowance repo
    -- User management
    :<|> handleListUsers repo
    :<|> handleCreateUser repo
    :<|> handleDeleteUser repo
    -- Hint sessions
    :<|> handleListHints repo
    :<|> handleAddHint repo
    :<|> handleRevertHint repo
    :<|> handleApplyHints repo
    :<|> handleRebaseHints repo

-- | Combined REST + RPC server.
fullServer :: Repository -> Server FullAPI
fullServer repo = server repo :<|> rpcServer repo

-- -----------------------------------------------------------------
-- Skills / Stations / Shifts
-- -----------------------------------------------------------------

handleListSkills :: Repository -> Handler [(SkillId, Skill)]
handleListSkills repo = liftIO $ SW.listSkills repo

handleListStations :: Repository -> Handler [(Int, String)]
handleListStations repo = do
    stations <- liftIO $ SW.listStations repo
    pure [(i, n) | (StationId i, n) <- stations]

handleListShifts :: Repository -> Handler [ShiftDef]
handleListShifts repo = liftIO $ repoLoadShifts repo

-- -----------------------------------------------------------------
-- Schedules
-- -----------------------------------------------------------------

handleListSchedules :: Repository -> Handler [String]
handleListSchedules repo = liftIO $ SS.listSchedules repo

handleGetSchedule :: Repository -> String -> Handler Schedule
handleGetSchedule repo name = do
    mSched <- liftIO $ SS.getSchedule repo name
    case mSched of
        Nothing -> throwApiError (NotFound ("Schedule not found: " ++ name))
        Just s  -> pure s

handleDeleteSchedule :: Repository -> String -> Handler NoContent
handleDeleteSchedule repo name = do
    liftIO $ SS.deleteSchedule repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Drafts
-- -----------------------------------------------------------------

handleListDrafts :: Repository -> Handler [DraftInfo]
handleListDrafts repo = liftIO $ SD.listDrafts repo

handleCreateDraft :: Repository -> CreateDraftReq -> Handler DraftCreatedResp
handleCreateDraft repo req = do
    result <- liftIO $ SD.createDraft repo (cdrDateFrom req) (cdrDateTo req)
    case result of
        Left msg  -> throwApiError (Conflict msg)
        Right did -> pure (DraftCreatedResp did)

handleGetDraft :: Repository -> Int -> Handler DraftInfo
handleGetDraft repo did = do
    mDraft <- liftIO $ SD.loadDraft repo did
    case mDraft of
        Nothing -> throwApiError (NotFound "Draft not found")
        Just d  -> pure d

handleGenerateDraft :: Repository -> Int -> GenerateDraftReq -> Handler ScheduleResult
handleGenerateDraft repo did req = do
    let workers = Set.fromList (map WorkerId (gdrWorkerIds req))
    result <- liftIO $ SD.generateDraft repo did workers
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right r  -> pure r

handleCommitDraft :: Repository -> Int -> CommitDraftReq -> Handler NoContent
handleCommitDraft repo did req = do
    result <- liftIO $ SD.commitDraft repo did (cmrNote req)
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> pure NoContent

handleDiscardDraft :: Repository -> Int -> Handler NoContent
handleDiscardDraft repo did = do
    result <- liftIO $ SD.discardDraft repo did
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> pure NoContent

-- -----------------------------------------------------------------
-- Calendar
-- -----------------------------------------------------------------

handleGetCalendar :: Repository -> Maybe Day -> Maybe Day -> Handler Schedule
handleGetCalendar repo mFrom mTo =
    case (mFrom, mTo) of
        (Just from, Just to) -> liftIO $ SC.loadCalendarSlice repo from to
        _ -> throwApiError (BadRequest "Both 'from' and 'to' query params are required")

handleListCalendarHistory :: Repository -> Handler [CalendarCommit]
handleListCalendarHistory repo = liftIO $ SC.listCalendarHistory repo

handleGetCalendarCommit :: Repository -> Int -> Handler Schedule
handleGetCalendarCommit repo cid = liftIO $ SC.viewCommit repo cid

-- -----------------------------------------------------------------
-- Absences
-- -----------------------------------------------------------------

handleListPendingAbsences :: Repository -> Handler [AbsenceRequest]
handleListPendingAbsences repo = liftIO $ SA.listPendingAbsences repo

handleRequestAbsence :: Repository -> RequestAbsenceReq -> Handler AbsenceCreatedResp
handleRequestAbsence repo req = do
    result <- liftIO $ SA.requestAbsenceService repo
        (WorkerId (rarWorkerId req))
        (AbsenceTypeId (rarTypeId req))
        (rarFrom req)
        (rarTo req)
    case result of
        Left SA.UnknownAbsenceType -> throwApiError (BadRequest "Unknown absence type")
        Left err -> throwApiError (InternalError (show err))
        Right (AbsenceId aid) -> pure (AbsenceCreatedResp aid)

handleApproveAbsence :: Repository -> Int -> Handler NoContent
handleApproveAbsence repo aid = do
    result <- liftIO $ SA.approveAbsenceService repo (AbsenceId aid)
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left SA.AbsenceAllowanceExceeded -> throwApiError (Conflict "Allowance exceeded")
        Left err -> throwApiError (InternalError (show err))
        Right () -> pure NoContent

handleRejectAbsence :: Repository -> Int -> Handler NoContent
handleRejectAbsence repo aid = do
    result <- liftIO $ SA.rejectAbsenceService repo (AbsenceId aid)
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left err -> throwApiError (InternalError (show err))
        Right () -> pure NoContent

-- -----------------------------------------------------------------
-- Config (read)
-- -----------------------------------------------------------------

handleGetConfig :: Repository -> Handler [(String, Double)]
handleGetConfig repo = liftIO $ SCfg.listConfigParams repo

-- -----------------------------------------------------------------
-- Skill CRUD
-- -----------------------------------------------------------------

handleCreateSkill :: Repository -> CreateSkillReq -> Handler NoContent
handleCreateSkill repo req = do
    liftIO $ SW.addSkill repo (SkillId (csrId req)) (csrName req) (csrDescription req)
    pure NoContent

handleDeleteSkill :: Repository -> Int -> Handler NoContent
handleDeleteSkill repo sid = do
    liftIO $ SW.removeSkill repo (SkillId sid)
    pure NoContent

-- -----------------------------------------------------------------
-- Station CRUD
-- -----------------------------------------------------------------

handleCreateStation :: Repository -> CreateStationReq -> Handler NoContent
handleCreateStation repo req = do
    liftIO $ SW.addStation repo (StationId (cstrId req)) (cstrName req)
    pure NoContent

handleDeleteStation :: Repository -> Int -> Handler NoContent
handleDeleteStation repo sid = do
    liftIO $ SW.removeStation repo (StationId sid)
    pure NoContent

handleSetStationHours :: Repository -> Int -> SetStationHoursReq -> Handler NoContent
handleSetStationHours repo sid req = do
    liftIO $ SW.setStationHours repo (StationId sid) (sshrStart req) (sshrEnd req)
    pure NoContent

handleSetStationClosure :: Repository -> Int -> SetStationClosureReq -> Handler NoContent
handleSetStationClosure repo sid req = do
    liftIO $ SW.closeStationDay repo (StationId sid) (sscrDay req)
    pure NoContent

-- -----------------------------------------------------------------
-- Shift CRUD
-- -----------------------------------------------------------------

handleCreateShift :: Repository -> CreateShiftReq -> Handler NoContent
handleCreateShift repo req = do
    liftIO $ repoSaveShift repo (ShiftDef (cshrName req) (cshrStart req) (cshrEnd req))
    pure NoContent

handleDeleteShift :: Repository -> String -> Handler NoContent
handleDeleteShift repo name = do
    liftIO $ repoDeleteShift repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Worker configuration
-- -----------------------------------------------------------------

handleSetWorkerHours :: Repository -> Int -> SetWorkerHoursReq -> Handler NoContent
handleSetWorkerHours repo wid req = do
    liftIO $ SW.setMaxHours repo (WorkerId wid) (fromIntegral (swhrHours req))
    pure NoContent

handleSetWorkerOvertime :: Repository -> Int -> SetWorkerOvertimeReq -> Handler NoContent
handleSetWorkerOvertime repo wid req = do
    _ <- liftIO $ SW.setOvertimeOptIn repo (WorkerId wid) (sworOptIn req)
    pure NoContent

handleSetWorkerPrefs :: Repository -> Int -> SetWorkerPrefsReq -> Handler NoContent
handleSetWorkerPrefs repo wid req = do
    liftIO $ SW.setStationPreferences repo (WorkerId wid)
        (map StationId (swprStationIds req))
    pure NoContent

handleSetWorkerVariety :: Repository -> Int -> SetWorkerVarietyReq -> Handler NoContent
handleSetWorkerVariety repo wid req = do
    liftIO $ SW.setVarietyPreference repo (WorkerId wid) (swvrPrefer req)
    pure NoContent

handleSetWorkerShiftPrefs :: Repository -> Int -> SetWorkerShiftPrefsReq -> Handler NoContent
handleSetWorkerShiftPrefs repo wid req = do
    liftIO $ SW.setShiftPreferences repo (WorkerId wid) (swsprShifts req)
    pure NoContent

handleSetWorkerWeekendOnly :: Repository -> Int -> SetWorkerWeekendOnlyReq -> Handler NoContent
handleSetWorkerWeekendOnly repo wid req = do
    liftIO $ SW.setWeekendOnly repo (WorkerId wid) (swwoVal req)
    pure NoContent

handleSetWorkerSeniority :: Repository -> Int -> SetWorkerSeniorityReq -> Handler NoContent
handleSetWorkerSeniority repo wid req = do
    liftIO $ SW.setSeniority repo (WorkerId wid) (swsrLevel req)
    pure NoContent

handleSetWorkerCrossTraining :: Repository -> Int -> SetWorkerCrossTrainingReq -> Handler NoContent
handleSetWorkerCrossTraining repo wid req = do
    liftIO $ SW.addCrossTraining repo (WorkerId wid) (SkillId (swctrSkillId req))
    pure NoContent

handleSetWorkerEmploymentStatus :: Repository -> Int -> SetWorkerEmploymentStatusReq -> Handler NoContent
handleSetWorkerEmploymentStatus repo wid req = do
    _ <- liftIO $ SW.setEmploymentStatus repo (WorkerId wid) (swesStatus req)
    pure NoContent

handleSetWorkerOvertimeModel :: Repository -> Int -> SetWorkerOvertimeModelReq -> Handler NoContent
handleSetWorkerOvertimeModel repo wid req = do
    liftIO $ SW.setOvertimeModel repo (WorkerId wid) (swomModel req)
    pure NoContent

handleSetWorkerPayTracking :: Repository -> Int -> SetWorkerPayTrackingReq -> Handler NoContent
handleSetWorkerPayTracking repo wid req = do
    liftIO $ SW.setPayPeriodTracking repo (WorkerId wid) (swptTracking req)
    pure NoContent

handleSetWorkerTemp :: Repository -> Int -> SetWorkerTempReq -> Handler NoContent
handleSetWorkerTemp repo wid req = do
    liftIO $ SW.setTempFlag repo (WorkerId wid) (swtTemp req)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker skill grant / revoke
-- -----------------------------------------------------------------

handleGrantWorkerSkill :: Repository -> Int -> Int -> Handler NoContent
handleGrantWorkerSkill repo wid sid = do
    liftIO $ SW.grantWorkerSkill repo (WorkerId wid) (SkillId sid)
    pure NoContent

handleRevokeWorkerSkill :: Repository -> Int -> Int -> Handler NoContent
handleRevokeWorkerSkill repo wid sid = do
    liftIO $ SW.revokeWorkerSkill repo (WorkerId wid) (SkillId sid)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker pairing
-- -----------------------------------------------------------------

handleAvoidPairing :: Repository -> Int -> WorkerPairingReq -> Handler NoContent
handleAvoidPairing repo wid req = do
    liftIO $ SW.addAvoidPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    pure NoContent

handlePreferPairing :: Repository -> Int -> WorkerPairingReq -> Handler NoContent
handlePreferPairing repo wid req = do
    liftIO $ SW.addPreferPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    pure NoContent

-- -----------------------------------------------------------------
-- Pins
-- -----------------------------------------------------------------

handleListPins :: Repository -> Handler [PinnedAssignment]
handleListPins repo = liftIO $ SW.listPins repo

handleAddPin :: Repository -> PinnedAssignment -> Handler NoContent
handleAddPin repo pin = do
    liftIO $ SW.addPin repo pin
    pure NoContent

handleRemovePin :: Repository -> PinnedAssignment -> Handler NoContent
handleRemovePin repo pin = do
    liftIO $ SW.removePin repo pin
    pure NoContent

-- -----------------------------------------------------------------
-- Calendar mutations
-- -----------------------------------------------------------------

handleUnfreeze :: UnfreezeReq -> Handler NoContent
handleUnfreeze _req = do
    -- Unfreeze is a session-level operation; the REST endpoint acknowledges
    -- the request. Full session integration happens in the RPC layer.
    pure NoContent

handleFreezeStatus :: Handler FreezeStatusResp
handleFreezeStatus = do
    line <- liftIO SF.computeFreezeLine
    pure (FreezeStatusResp line)

-- -----------------------------------------------------------------
-- Config writes
-- -----------------------------------------------------------------

handleSetConfig :: Repository -> String -> SetConfigReq -> Handler NoContent
handleSetConfig repo key req = do
    result <- liftIO $ SCfg.setConfigParam repo key (scrValue req)
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown config key: " ++ key))
        Just _  -> pure NoContent

handleApplyPreset :: Repository -> String -> Handler NoContent
handleApplyPreset repo name = do
    result <- liftIO $ SCfg.applyPreset repo name
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown preset: " ++ name))
        Just _  -> pure NoContent

handleResetConfig :: Repository -> Handler NoContent
handleResetConfig repo = do
    liftIO $ SCfg.saveConfig repo =<< SCfg.loadConfig repo
    pure NoContent

handleSetPayPeriod :: Repository -> SetPayPeriodReq -> Handler NoContent
handleSetPayPeriod repo req = do
    case parsePayPeriodType (sprType req) of
        Nothing -> throwApiError (BadRequest ("Unknown pay period type: " ++ sprType req))
        Just pt -> do
            liftIO $ SCfg.savePayPeriodConfig repo
                (PayPeriodConfig pt (sprAnchorDate req))
            pure NoContent

-- -----------------------------------------------------------------
-- Audit log
-- -----------------------------------------------------------------

handleGetAuditLog :: Repository -> Handler [AuditEntry]
handleGetAuditLog repo = liftIO $ repoGetAuditLog repo

-- -----------------------------------------------------------------
-- Checkpoints
-- -----------------------------------------------------------------

handleCreateCheckpoint :: Repository -> CreateCheckpointReq -> Handler NoContent
handleCreateCheckpoint repo req = do
    liftIO $ repoSavepoint repo (ccrName req)
    pure NoContent

handleCommitCheckpoint :: Repository -> String -> Handler NoContent
handleCommitCheckpoint repo name = do
    liftIO $ repoRelease repo name
    pure NoContent

handleRollbackCheckpoint :: Repository -> String -> Handler NoContent
handleRollbackCheckpoint repo name = do
    liftIO $ repoRollbackTo repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Import / Export
-- -----------------------------------------------------------------

handleExport :: Repository -> Handler ExportResp
handleExport repo = do
    dat <- liftIO $ Exp.gatherExport repo Nothing
    pure (ExportResp dat)

handleImport :: Repository -> ImportReq -> Handler ImportResp
handleImport repo req = do
    msgs <- liftIO $ Exp.applyImport repo (irData req)
    pure (ImportResp msgs)

-- -----------------------------------------------------------------
-- Absence type management
-- -----------------------------------------------------------------

handleCreateAbsenceType :: Repository -> CreateAbsenceTypeReq -> Handler NoContent
handleCreateAbsenceType repo req = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let atId = AbsenceTypeId (catrId req)
        newType = AbsenceType (catrName req) (catrCountsAgainstAllowance req)
        ctx' = ctx { acTypes = Map.insert atId newType (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

handleDeleteAbsenceType :: Repository -> Int -> Handler NoContent
handleDeleteAbsenceType repo atid = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let ctx' = ctx { acTypes = Map.delete (AbsenceTypeId atid) (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

handleSetAbsenceAllowance :: Repository -> Int -> SetAbsenceAllowanceReq -> Handler NoContent
handleSetAbsenceAllowance repo atid req = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let key = (WorkerId (saarWorkerId req), AbsenceTypeId atid)
        ctx' = ctx { acYearlyAllowance = Map.insert key (saarAllowance req) (acYearlyAllowance ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

-- -----------------------------------------------------------------
-- User management
-- -----------------------------------------------------------------

handleListUsers :: Repository -> Handler [User]
handleListUsers repo = liftIO $ repoListUsers repo

handleCreateUser :: Repository -> CreateUserReq -> Handler NoContent
handleCreateUser repo req = do
    result <- liftIO $ SAuth.register repo
        (curUsername req) (curPassword req) (curRole req) (WorkerId (curWorkerId req))
    case result of
        Left SAuth.UsernameTaken -> throwApiError (Conflict "Username already taken")
        Left err -> throwApiError (InternalError (show err))
        Right _ -> pure NoContent

handleDeleteUser :: Repository -> String -> Handler NoContent
handleDeleteUser repo uname = do
    mUser <- liftIO $ repoGetUserByName repo uname
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ uname))
        Just u  -> do
            liftIO $ repoDeleteUser repo (userId u)
            pure NoContent

-- -----------------------------------------------------------------
-- Hint sessions
-- -----------------------------------------------------------------

handleListHints :: Repository -> Maybe Int -> Maybe Int -> Handler [Hint]
handleListHints repo mSid mDid =
    case (mSid, mDid) of
        (Just sid, Just did) -> do
            mRec <- liftIO $ repoLoadHintSession repo (SessionId sid) did
            case mRec of
                Nothing  -> pure []
                Just rec -> pure (hsHints rec)
        _ -> throwApiError (BadRequest "Both sessionId and draftId query params are required")

handleAddHint :: Repository -> AddHintReq -> Handler [Hint]
handleAddHint repo req = do
    let sid = SessionId (ahrSessionId req)
        did = ahrDraftId req
    mRec <- liftIO $ repoLoadHintSession repo sid did
    let currentHints = maybe [] hsHints mRec
        checkpoint   = maybe 0 hsCheckpoint mRec
        newHints     = currentHints ++ [ahrHint req]
    liftIO $ repoSaveHintSession repo sid did newHints checkpoint
    pure newHints

handleRevertHint :: Repository -> HintSessionRef -> Handler [Hint]
handleRevertHint repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    mRec <- liftIO $ repoLoadHintSession repo sid did
    case mRec of
        Nothing  -> throwApiError (NotFound "No hint session found")
        Just rec -> do
            let hints = hsHints rec
            if null hints
                then throwApiError (BadRequest "No hints to revert")
                else do
                    let reverted = init hints
                    liftIO $ repoSaveHintSession repo sid did reverted (hsCheckpoint rec)
                    pure reverted

handleApplyHints :: Repository -> HintSessionRef -> Handler NoContent
handleApplyHints repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    liftIO $ repoDeleteHintSession repo sid did
    pure NoContent

handleRebaseHints :: Repository -> HintSessionRef -> Handler RebaseResultResp
handleRebaseHints repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    mRec <- liftIO $ repoLoadHintSession repo sid did
    case mRec of
        Nothing -> throwApiError (NotFound "No hint session found")
        Just rec -> do
            entries <- liftIO $ repoAuditSince repo (hsCheckpoint rec)
            let result = SHR.rebaseSession did entries (hsHints rec)
            case result of
                SHR.UpToDate ->
                    pure (RebaseResultResp "up-to-date" "No changes since last checkpoint")
                SHR.AutoRebase n -> do
                    -- Update checkpoint to latest audit entry
                    let newCheckpoint = if null entries then hsCheckpoint rec
                                        else aeId (last entries)
                    liftIO $ repoSaveHintSession repo sid did (hsHints rec) newCheckpoint
                    pure (RebaseResultResp "auto-rebase"
                        ("Auto-rebased over " ++ show n ++ " compatible changes"))
                SHR.HasConflicts _ ->
                    pure (RebaseResultResp "has-conflicts"
                        "Some changes conflict with current hints")
                SHR.SessionInvalid msg ->
                    pure (RebaseResultResp "session-invalid" msg)
