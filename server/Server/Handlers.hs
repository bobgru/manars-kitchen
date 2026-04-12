{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Server.Handlers
    ( protectedServer
    , fullServer
    ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day)
import Servant

import Auth.Types (User(..), Role(..))
import Domain.Types (WorkerId(..), StationId(..), AbsenceId(..), AbsenceTypeId(..), SkillId(..), Schedule)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef(..))
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest(..), AbsenceType(..), AbsenceContext(..))
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
import Server.Api (RawAPI, FullAPI)
import Server.Json
import Server.Error
import Server.Auth (handleLogin, handleLogout, requireAdmin, requireSelfOrAdmin)
import Server.Rpc (RpcAPI, rpcServer)

-- | REST server for protected endpoints. User is threaded through from AuthProtect.
server :: Repository -> User -> Server RawAPI
server repo user =
    -- Logout
         handleLogout repo user
    -- Original endpoints
    :<|> handleListSkills repo
    :<|> handleListStations repo
    :<|> handleListShifts repo
    :<|> handleListSchedules repo
    :<|> handleGetSchedule repo
    :<|> handleDeleteSchedule repo user
    :<|> handleListDrafts repo
    :<|> handleCreateDraft repo user
    :<|> handleGetDraft repo
    :<|> handleGenerateDraft repo user
    :<|> handleCommitDraft repo user
    :<|> handleDiscardDraft repo user
    :<|> handleGetCalendar repo
    :<|> handleListCalendarHistory repo
    :<|> handleGetCalendarCommit repo
    :<|> handleListPendingAbsences repo user
    :<|> handleRequestAbsence repo user
    :<|> handleApproveAbsence repo user
    :<|> handleRejectAbsence repo user
    :<|> handleGetConfig repo
    -- Skill CRUD
    :<|> handleCreateSkill repo user
    :<|> handleDeleteSkill repo user
    -- Station CRUD
    :<|> handleCreateStation repo user
    :<|> handleDeleteStation repo user
    :<|> handleSetStationHours repo user
    :<|> handleSetStationClosure repo user
    -- Shift CRUD
    :<|> handleCreateShift repo user
    :<|> handleDeleteShift repo user
    -- Worker configuration
    :<|> handleSetWorkerHours repo user
    :<|> handleSetWorkerOvertime repo user
    :<|> handleSetWorkerPrefs repo user
    :<|> handleSetWorkerVariety repo user
    :<|> handleSetWorkerShiftPrefs repo user
    :<|> handleSetWorkerWeekendOnly repo user
    :<|> handleSetWorkerSeniority repo user
    :<|> handleSetWorkerCrossTraining repo user
    :<|> handleSetWorkerEmploymentStatus repo user
    :<|> handleSetWorkerOvertimeModel repo user
    :<|> handleSetWorkerPayTracking repo user
    :<|> handleSetWorkerTemp repo user
    -- Worker skill grant/revoke
    :<|> handleGrantWorkerSkill repo user
    :<|> handleRevokeWorkerSkill repo user
    -- Worker pairing
    :<|> handleAvoidPairing repo user
    :<|> handlePreferPairing repo user
    -- Pins
    :<|> handleListPins repo
    :<|> handleAddPin repo user
    :<|> handleRemovePin repo user
    -- Calendar mutations
    :<|> handleUnfreeze user
    :<|> handleFreezeStatus
    -- Config writes
    :<|> handleSetConfig repo user
    :<|> handleApplyPreset repo user
    :<|> handleResetConfig repo user
    :<|> handleSetPayPeriod repo user
    -- Audit
    :<|> handleGetAuditLog repo user
    -- Checkpoints
    :<|> handleCreateCheckpoint repo user
    :<|> handleCommitCheckpoint repo user
    :<|> handleRollbackCheckpoint repo user
    -- Import/Export
    :<|> handleExport repo user
    :<|> handleImport repo user
    -- Absence type management
    :<|> handleCreateAbsenceType repo user
    :<|> handleDeleteAbsenceType repo user
    :<|> handleSetAbsenceAllowance repo user
    -- User management
    :<|> handleListUsers repo user
    :<|> handleCreateUser repo user
    :<|> handleDeleteUser repo user
    -- Hint sessions
    :<|> handleListHints repo user
    :<|> handleAddHint repo user
    :<|> handleRevertHint repo user
    :<|> handleApplyHints repo user
    :<|> handleRebaseHints repo user

-- | Protected server: REST + RPC, both receiving User from AuthProtect.
protectedServer :: Repository -> User -> Server (RawAPI :<|> RpcAPI)
protectedServer repo user = server repo user :<|> rpcServer repo user

-- | Combined server: Public + Protected.
fullServer :: Repository -> Server FullAPI
fullServer repo =
         handleLogin repo
    :<|> protectedServer repo

-- -----------------------------------------------------------------
-- Skills / Stations / Shifts (read — no auth guard needed)
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

handleDeleteSchedule :: Repository -> User -> String -> Handler NoContent
handleDeleteSchedule repo user name = do
    requireAdmin user
    liftIO $ SS.deleteSchedule repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Drafts
-- -----------------------------------------------------------------

handleListDrafts :: Repository -> Handler [DraftInfo]
handleListDrafts repo = liftIO $ SD.listDrafts repo

handleCreateDraft :: Repository -> User -> CreateDraftReq -> Handler DraftCreatedResp
handleCreateDraft repo user req = do
    requireAdmin user
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

handleGenerateDraft :: Repository -> User -> Int -> GenerateDraftReq -> Handler ScheduleResult
handleGenerateDraft repo user did req = do
    requireAdmin user
    let workers = Set.fromList (map WorkerId (gdrWorkerIds req))
    result <- liftIO $ SD.generateDraft repo did workers
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right r  -> pure r

handleCommitDraft :: Repository -> User -> Int -> CommitDraftReq -> Handler NoContent
handleCommitDraft repo user did req = do
    requireAdmin user
    result <- liftIO $ SD.commitDraft repo did (cmrNote req)
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> pure NoContent

handleDiscardDraft :: Repository -> User -> Int -> Handler NoContent
handleDiscardDraft repo user did = do
    requireAdmin user
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

handleListPendingAbsences :: Repository -> User -> Handler [AbsenceRequest]
handleListPendingAbsences repo user = do
    allPending <- liftIO $ SA.listPendingAbsences repo
    case userRole user of
        Admin  -> pure allPending
        Normal -> pure $ filter (\a -> arWorker a == userWorkerId user) allPending

handleRequestAbsence :: Repository -> User -> RequestAbsenceReq -> Handler AbsenceCreatedResp
handleRequestAbsence repo user req = do
    requireSelfOrAdmin user (rarWorkerId req)
    result <- liftIO $ SA.requestAbsenceService repo
        (WorkerId (rarWorkerId req))
        (AbsenceTypeId (rarTypeId req))
        (rarFrom req)
        (rarTo req)
    case result of
        Left SA.UnknownAbsenceType -> throwApiError (BadRequest "Unknown absence type")
        Left err -> throwApiError (InternalError (show err))
        Right (AbsenceId aid) -> pure (AbsenceCreatedResp aid)

handleApproveAbsence :: Repository -> User -> Int -> Handler NoContent
handleApproveAbsence repo user aid = do
    requireAdmin user
    result <- liftIO $ SA.approveAbsenceService repo (AbsenceId aid)
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left SA.AbsenceAllowanceExceeded -> throwApiError (Conflict "Allowance exceeded")
        Left err -> throwApiError (InternalError (show err))
        Right () -> pure NoContent

handleRejectAbsence :: Repository -> User -> Int -> Handler NoContent
handleRejectAbsence repo user aid = do
    requireAdmin user
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

handleCreateSkill :: Repository -> User -> CreateSkillReq -> Handler NoContent
handleCreateSkill repo user req = do
    requireAdmin user
    liftIO $ SW.addSkill repo (SkillId (csrId req)) (csrName req) (csrDescription req)
    pure NoContent

handleDeleteSkill :: Repository -> User -> Int -> Handler NoContent
handleDeleteSkill repo user sid = do
    requireAdmin user
    liftIO $ SW.removeSkill repo (SkillId sid)
    pure NoContent

-- -----------------------------------------------------------------
-- Station CRUD
-- -----------------------------------------------------------------

handleCreateStation :: Repository -> User -> CreateStationReq -> Handler NoContent
handleCreateStation repo user req = do
    requireAdmin user
    liftIO $ SW.addStation repo (StationId (cstrId req)) (cstrName req)
    pure NoContent

handleDeleteStation :: Repository -> User -> Int -> Handler NoContent
handleDeleteStation repo user sid = do
    requireAdmin user
    liftIO $ SW.removeStation repo (StationId sid)
    pure NoContent

handleSetStationHours :: Repository -> User -> Int -> SetStationHoursReq -> Handler NoContent
handleSetStationHours repo user sid req = do
    requireAdmin user
    liftIO $ SW.setStationHours repo (StationId sid) (sshrStart req) (sshrEnd req)
    pure NoContent

handleSetStationClosure :: Repository -> User -> Int -> SetStationClosureReq -> Handler NoContent
handleSetStationClosure repo user sid req = do
    requireAdmin user
    liftIO $ SW.closeStationDay repo (StationId sid) (sscrDay req)
    pure NoContent

-- -----------------------------------------------------------------
-- Shift CRUD
-- -----------------------------------------------------------------

handleCreateShift :: Repository -> User -> CreateShiftReq -> Handler NoContent
handleCreateShift repo user req = do
    requireAdmin user
    liftIO $ repoSaveShift repo (ShiftDef (cshrName req) (cshrStart req) (cshrEnd req))
    pure NoContent

handleDeleteShift :: Repository -> User -> String -> Handler NoContent
handleDeleteShift repo user name = do
    requireAdmin user
    liftIO $ repoDeleteShift repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Worker configuration
-- -----------------------------------------------------------------

handleSetWorkerHours :: Repository -> User -> Int -> SetWorkerHoursReq -> Handler NoContent
handleSetWorkerHours repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setMaxHours repo (WorkerId wid) (fromIntegral (swhrHours req))
    pure NoContent

handleSetWorkerOvertime :: Repository -> User -> Int -> SetWorkerOvertimeReq -> Handler NoContent
handleSetWorkerOvertime repo user wid req = do
    requireSelfOrAdmin user wid
    _ <- liftIO $ SW.setOvertimeOptIn repo (WorkerId wid) (sworOptIn req)
    pure NoContent

handleSetWorkerPrefs :: Repository -> User -> Int -> SetWorkerPrefsReq -> Handler NoContent
handleSetWorkerPrefs repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setStationPreferences repo (WorkerId wid)
        (map StationId (swprStationIds req))
    pure NoContent

handleSetWorkerVariety :: Repository -> User -> Int -> SetWorkerVarietyReq -> Handler NoContent
handleSetWorkerVariety repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setVarietyPreference repo (WorkerId wid) (swvrPrefer req)
    pure NoContent

handleSetWorkerShiftPrefs :: Repository -> User -> Int -> SetWorkerShiftPrefsReq -> Handler NoContent
handleSetWorkerShiftPrefs repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setShiftPreferences repo (WorkerId wid) (swsprShifts req)
    pure NoContent

handleSetWorkerWeekendOnly :: Repository -> User -> Int -> SetWorkerWeekendOnlyReq -> Handler NoContent
handleSetWorkerWeekendOnly repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setWeekendOnly repo (WorkerId wid) (swwoVal req)
    pure NoContent

handleSetWorkerSeniority :: Repository -> User -> Int -> SetWorkerSeniorityReq -> Handler NoContent
handleSetWorkerSeniority repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setSeniority repo (WorkerId wid) (swsrLevel req)
    pure NoContent

handleSetWorkerCrossTraining :: Repository -> User -> Int -> SetWorkerCrossTrainingReq -> Handler NoContent
handleSetWorkerCrossTraining repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.addCrossTraining repo (WorkerId wid) (SkillId (swctrSkillId req))
    pure NoContent

handleSetWorkerEmploymentStatus :: Repository -> User -> Int -> SetWorkerEmploymentStatusReq -> Handler NoContent
handleSetWorkerEmploymentStatus repo user wid req = do
    requireSelfOrAdmin user wid
    _ <- liftIO $ SW.setEmploymentStatus repo (WorkerId wid) (swesStatus req)
    pure NoContent

handleSetWorkerOvertimeModel :: Repository -> User -> Int -> SetWorkerOvertimeModelReq -> Handler NoContent
handleSetWorkerOvertimeModel repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setOvertimeModel repo (WorkerId wid) (swomModel req)
    pure NoContent

handleSetWorkerPayTracking :: Repository -> User -> Int -> SetWorkerPayTrackingReq -> Handler NoContent
handleSetWorkerPayTracking repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setPayPeriodTracking repo (WorkerId wid) (swptTracking req)
    pure NoContent

handleSetWorkerTemp :: Repository -> User -> Int -> SetWorkerTempReq -> Handler NoContent
handleSetWorkerTemp repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.setTempFlag repo (WorkerId wid) (swtTemp req)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker skill grant / revoke
-- -----------------------------------------------------------------

handleGrantWorkerSkill :: Repository -> User -> Int -> Int -> Handler NoContent
handleGrantWorkerSkill repo user wid sid = do
    requireSelfOrAdmin user wid
    liftIO $ SW.grantWorkerSkill repo (WorkerId wid) (SkillId sid)
    pure NoContent

handleRevokeWorkerSkill :: Repository -> User -> Int -> Int -> Handler NoContent
handleRevokeWorkerSkill repo user wid sid = do
    requireSelfOrAdmin user wid
    liftIO $ SW.revokeWorkerSkill repo (WorkerId wid) (SkillId sid)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker pairing
-- -----------------------------------------------------------------

handleAvoidPairing :: Repository -> User -> Int -> WorkerPairingReq -> Handler NoContent
handleAvoidPairing repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.addAvoidPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    pure NoContent

handlePreferPairing :: Repository -> User -> Int -> WorkerPairingReq -> Handler NoContent
handlePreferPairing repo user wid req = do
    requireSelfOrAdmin user wid
    liftIO $ SW.addPreferPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    pure NoContent

-- -----------------------------------------------------------------
-- Pins
-- -----------------------------------------------------------------

handleListPins :: Repository -> Handler [PinnedAssignment]
handleListPins repo = liftIO $ SW.listPins repo

handleAddPin :: Repository -> User -> PinnedAssignment -> Handler NoContent
handleAddPin repo user pin = do
    requireAdmin user
    liftIO $ SW.addPin repo pin
    pure NoContent

handleRemovePin :: Repository -> User -> PinnedAssignment -> Handler NoContent
handleRemovePin repo user pin = do
    requireAdmin user
    liftIO $ SW.removePin repo pin
    pure NoContent

-- -----------------------------------------------------------------
-- Calendar mutations
-- -----------------------------------------------------------------

handleUnfreeze :: User -> UnfreezeReq -> Handler NoContent
handleUnfreeze user _req = do
    requireAdmin user
    pure NoContent

handleFreezeStatus :: Handler FreezeStatusResp
handleFreezeStatus = do
    line <- liftIO SF.computeFreezeLine
    pure (FreezeStatusResp line)

-- -----------------------------------------------------------------
-- Config writes
-- -----------------------------------------------------------------

handleSetConfig :: Repository -> User -> String -> SetConfigReq -> Handler NoContent
handleSetConfig repo user key req = do
    requireAdmin user
    result <- liftIO $ SCfg.setConfigParam repo key (scrValue req)
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown config key: " ++ key))
        Just _  -> pure NoContent

handleApplyPreset :: Repository -> User -> String -> Handler NoContent
handleApplyPreset repo user name = do
    requireAdmin user
    result <- liftIO $ SCfg.applyPreset repo name
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown preset: " ++ name))
        Just _  -> pure NoContent

handleResetConfig :: Repository -> User -> Handler NoContent
handleResetConfig repo user = do
    requireAdmin user
    liftIO $ SCfg.saveConfig repo =<< SCfg.loadConfig repo
    pure NoContent

handleSetPayPeriod :: Repository -> User -> SetPayPeriodReq -> Handler NoContent
handleSetPayPeriod repo user req = do
    requireAdmin user
    case parsePayPeriodType (sprType req) of
        Nothing -> throwApiError (BadRequest ("Unknown pay period type: " ++ sprType req))
        Just pt -> do
            liftIO $ SCfg.savePayPeriodConfig repo
                (PayPeriodConfig pt (sprAnchorDate req))
            pure NoContent

-- -----------------------------------------------------------------
-- Audit log
-- -----------------------------------------------------------------

handleGetAuditLog :: Repository -> User -> Handler [AuditEntry]
handleGetAuditLog repo user = do
    requireAdmin user
    liftIO $ repoGetAuditLog repo

-- -----------------------------------------------------------------
-- Checkpoints
-- -----------------------------------------------------------------

handleCreateCheckpoint :: Repository -> User -> CreateCheckpointReq -> Handler NoContent
handleCreateCheckpoint repo user req = do
    requireAdmin user
    liftIO $ repoSavepoint repo (ccrName req)
    pure NoContent

handleCommitCheckpoint :: Repository -> User -> String -> Handler NoContent
handleCommitCheckpoint repo user name = do
    requireAdmin user
    liftIO $ repoRelease repo name
    pure NoContent

handleRollbackCheckpoint :: Repository -> User -> String -> Handler NoContent
handleRollbackCheckpoint repo user name = do
    requireAdmin user
    liftIO $ repoRollbackTo repo name
    pure NoContent

-- -----------------------------------------------------------------
-- Import / Export
-- -----------------------------------------------------------------

handleExport :: Repository -> User -> Handler ExportResp
handleExport repo user = do
    requireAdmin user
    dat <- liftIO $ Exp.gatherExport repo Nothing
    pure (ExportResp dat)

handleImport :: Repository -> User -> ImportReq -> Handler ImportResp
handleImport repo user req = do
    requireAdmin user
    msgs <- liftIO $ Exp.applyImport repo (irData req)
    pure (ImportResp msgs)

-- -----------------------------------------------------------------
-- Absence type management
-- -----------------------------------------------------------------

handleCreateAbsenceType :: Repository -> User -> CreateAbsenceTypeReq -> Handler NoContent
handleCreateAbsenceType repo user req = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let atId = AbsenceTypeId (catrId req)
        newType = AbsenceType (catrName req) (catrCountsAgainstAllowance req)
        ctx' = ctx { acTypes = Map.insert atId newType (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

handleDeleteAbsenceType :: Repository -> User -> Int -> Handler NoContent
handleDeleteAbsenceType repo user atid = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let ctx' = ctx { acTypes = Map.delete (AbsenceTypeId atid) (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

handleSetAbsenceAllowance :: Repository -> User -> Int -> SetAbsenceAllowanceReq -> Handler NoContent
handleSetAbsenceAllowance repo user atid req = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let key = (WorkerId (saarWorkerId req), AbsenceTypeId atid)
        ctx' = ctx { acYearlyAllowance = Map.insert key (saarAllowance req) (acYearlyAllowance ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    pure NoContent

-- -----------------------------------------------------------------
-- User management
-- -----------------------------------------------------------------

handleListUsers :: Repository -> User -> Handler [User]
handleListUsers repo user = do
    requireAdmin user
    liftIO $ repoListUsers repo

handleCreateUser :: Repository -> User -> CreateUserReq -> Handler NoContent
handleCreateUser repo user req = do
    requireAdmin user
    result <- liftIO $ SAuth.register repo
        (curUsername req) (curPassword req) (curRole req) (WorkerId (curWorkerId req))
    case result of
        Left SAuth.UsernameTaken -> throwApiError (Conflict "Username already taken")
        Left err -> throwApiError (InternalError (show err))
        Right _ -> pure NoContent

handleDeleteUser :: Repository -> User -> String -> Handler NoContent
handleDeleteUser repo user uname = do
    requireAdmin user
    mUser <- liftIO $ repoGetUserByName repo uname
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ uname))
        Just u  -> do
            liftIO $ repoDeleteUser repo (userId u)
            pure NoContent

-- -----------------------------------------------------------------
-- Hint sessions
-- -----------------------------------------------------------------

handleListHints :: Repository -> User -> Maybe Int -> Maybe Int -> Handler [Hint]
handleListHints repo user mSid mDid =
    case (mSid, mDid) of
        (Just sid, Just did) -> do
            requireSessionOwner repo user (SessionId sid)
            mRec <- liftIO $ repoLoadHintSession repo (SessionId sid) did
            case mRec of
                Nothing  -> pure []
                Just rec -> pure (hsHints rec)
        _ -> throwApiError (BadRequest "Both sessionId and draftId query params are required")

handleAddHint :: Repository -> User -> AddHintReq -> Handler [Hint]
handleAddHint repo user req = do
    requireSessionOwner repo user (SessionId (ahrSessionId req))
    let sid = SessionId (ahrSessionId req)
        did = ahrDraftId req
    mRec <- liftIO $ repoLoadHintSession repo sid did
    let currentHints = maybe [] hsHints mRec
        checkpoint   = maybe 0 hsCheckpoint mRec
        newHints     = currentHints ++ [ahrHint req]
    liftIO $ repoSaveHintSession repo sid did newHints checkpoint
    pure newHints

handleRevertHint :: Repository -> User -> HintSessionRef -> Handler [Hint]
handleRevertHint repo user ref = do
    requireSessionOwner repo user (SessionId (hsrSessionId ref))
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

handleApplyHints :: Repository -> User -> HintSessionRef -> Handler NoContent
handleApplyHints repo user ref = do
    requireSessionOwner repo user (SessionId (hsrSessionId ref))
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    liftIO $ repoDeleteHintSession repo sid did
    pure NoContent

handleRebaseHints :: Repository -> User -> HintSessionRef -> Handler RebaseResultResp
handleRebaseHints repo user ref = do
    requireSessionOwner repo user (SessionId (hsrSessionId ref))
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

-- -----------------------------------------------------------------
-- Session ownership check
-- -----------------------------------------------------------------

-- | Ensure the authenticated user owns the given session (or is admin).
requireSessionOwner :: Repository -> User -> SessionId -> Handler ()
requireSessionOwner repo user sid = do
    case userRole user of
        Admin -> return ()
        Normal -> do
            mOwner <- liftIO $ repoGetSessionOwner repo sid
            case mOwner of
                Just owner | owner == userId user -> return ()
                _ -> throwApiError (Forbidden "Forbidden")
