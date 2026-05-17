{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Server.Handlers
    ( protectedServer
    , fullServer
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (toJSON, encode)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Time (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import Servant

import Auth.Types (User(..), UserId(..), Username(..), Role(..), userIdToWorkerId)
import Data.Text (Text)
import Domain.Types (WorkerId(..), StationId(..), Station(..), AbsenceId(..), AbsenceTypeId(..), SkillId(..), Schedule, workerStatusToText)
import Domain.Worker (OvertimeModel(..), PayPeriodTracking(..))
import Domain.Skill (Skill(..))
import Domain.Shift (ShiftDef(..))
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest(..), AbsenceType(..), AbsenceContext(..))
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment(..))
import Domain.PayPeriod (parsePayPeriodType, PayPeriodConfig(..))
import Repo.Types (Repository(..), DraftInfo, CalendarCommit, AuditEntry(..), SessionId(..), HintSessionRecord(..))
import qualified Service.Worker as SW
import qualified Service.User as SU
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
import Service.PubSub (TopicBus, CommandEvent, Source(..), AppBus(..), publishCommand)
import Server.Execute (ExecuteEnv(..), executeCommandText)
import Utils (shellQuote)

-- | Publish a command event from a REST handler.
logRest :: TopicBus CommandEvent -> User -> String -> Handler ()
logRest cmdBus user cmd = let Username uname = userName user
                          in liftIO $ publishCommand cmdBus GUI (T.unpack uname) cmd

-- | Resolve a skill name to a SkillId; throws 404 if not found.
resolveSkillName :: Repository -> Text -> Handler SkillId
resolveSkillName repo name = do
    skills <- liftIO $ repoListSkills repo
    let nameLower = T.toLower name
    case [sid | (sid, sk) <- skills, T.toLower (skillName sk) == nameLower] of
        (sid:_) -> pure sid
        []      -> throwApiError (NotFound ("Unknown skill: " ++ T.unpack name))

-- | Look up a skill name by ID; returns the ID as a string if not found.
lookupSkillName :: Repository -> SkillId -> IO String
lookupSkillName repo sid = do
    skills <- repoListSkills repo
    case lookup sid skills of
        Just sk -> return (T.unpack (skillName sk))
        Nothing -> let SkillId i = sid in return (show i)

-- | Resolve a station name to a StationId; throws 404 if not found.
resolveStationName :: Repository -> Text -> Handler StationId
resolveStationName repo name = do
    stations <- liftIO $ repoListStations repo
    let nameLower = T.toLower name
    case [sid | (sid, st) <- stations, T.toLower (stationName st) == nameLower] of
        (sid:_) -> pure sid
        []      -> throwApiError (NotFound ("Unknown station: " ++ T.unpack name))

-- | Look up a station name by ID; returns the ID as a string if not found.
lookupStationName :: Repository -> StationId -> IO Text
lookupStationName repo stid = do
    stations <- repoListStations repo
    case lookup stid stations of
        Just st -> return (stationName st)
        Nothing -> let StationId i = stid in return (T.pack (show i))

-- | Look up a worker name by ID; returns the ID as a string if not found.
lookupWorkerName :: Repository -> WorkerId -> IO String
lookupWorkerName repo wid = do
    users <- repoListUsers repo
    case [uname | u <- users, userIdToWorkerId (userId u) == wid, let Username uname = userName u] of
        (n:_) -> return (T.unpack n)
        []    -> let WorkerId i = wid in return (show i)

-- | REST server for protected endpoints. User is threaded through from AuthProtect.
server :: ExecuteEnv -> TopicBus CommandEvent -> Repository -> User -> Server RawAPI
server execEnv cmdBus repo user =
    -- Logout
         handleLogout repo user
    -- Original endpoints
    :<|> handleListStations repo
    :<|> handleListShifts repo
    :<|> handleListSchedules repo
    :<|> handleGetSchedule repo
    :<|> handleDeleteSchedule cmdBus repo user
    :<|> handleListDrafts repo
    :<|> handleCreateDraft repo user
    :<|> handleGetDraft repo
    :<|> handleGenerateDraft repo user
    :<|> handleCommitDraft cmdBus repo user
    :<|> handleDiscardDraft cmdBus repo user
    :<|> handleGetCalendar repo
    :<|> handleListCalendarHistory repo
    :<|> handleGetCalendarCommit repo
    :<|> handleListPendingAbsences repo user
    :<|> handleRequestAbsence cmdBus repo user
    :<|> handleApproveAbsence cmdBus repo user
    :<|> handleRejectAbsence cmdBus repo user
    :<|> handleGetConfig repo
    -- Skill CRUD
    :<|> handleListSkills repo
    :<|> handleCreateSkill cmdBus repo user
    :<|> handleDeleteSkill cmdBus repo user
    :<|> handleForceDeleteSkill execEnv repo user
    :<|> handleRenameSkill cmdBus repo user
    -- Skill implications
    :<|> handleListImplications repo
    :<|> handleAddImplication cmdBus repo user
    :<|> handleRemoveImplication cmdBus repo user
    -- Station CRUD
    :<|> handleCreateStation cmdBus repo user
    :<|> handleDeleteStation cmdBus repo user
    :<|> handleForceDeleteStation execEnv repo user
    :<|> handleRenameStation cmdBus repo user
    :<|> handleSetStationHours cmdBus repo user
    :<|> handleSetStationClosure cmdBus repo user
    -- Shift CRUD
    :<|> handleCreateShift cmdBus repo user
    :<|> handleDeleteShift cmdBus repo user
    -- Worker configuration
    :<|> handleSetWorkerHours cmdBus repo user
    :<|> handleSetWorkerOvertime cmdBus repo user
    :<|> handleSetWorkerPrefs cmdBus repo user
    :<|> handleSetWorkerVariety cmdBus repo user
    :<|> handleSetWorkerShiftPrefs cmdBus repo user
    :<|> handleSetWorkerWeekendOnly cmdBus repo user
    :<|> handleSetWorkerSeniority cmdBus repo user
    :<|> handleSetWorkerCrossTraining cmdBus repo user
    :<|> handleSetWorkerEmploymentStatus cmdBus repo user
    :<|> handleSetWorkerOvertimeModel cmdBus repo user
    :<|> handleSetWorkerPayTracking cmdBus repo user
    :<|> handleSetWorkerTemp cmdBus repo user
    -- Worker skill grant/revoke
    :<|> handleGrantWorkerSkill cmdBus repo user
    :<|> handleRevokeWorkerSkill cmdBus repo user
    -- Worker pairing
    :<|> handleAvoidPairing cmdBus repo user
    :<|> handlePreferPairing cmdBus repo user
    -- Pins
    :<|> handleListPins repo
    :<|> handleAddPin cmdBus repo user
    :<|> handleRemovePin cmdBus repo user
    -- Calendar mutations
    :<|> handleUnfreeze user
    :<|> handleFreezeStatus
    -- Config writes
    :<|> handleSetConfig cmdBus repo user
    :<|> handleApplyPreset cmdBus repo user
    :<|> handleResetConfig cmdBus repo user
    :<|> handleSetPayPeriod cmdBus repo user
    -- Audit
    :<|> handleGetAuditLog repo user
    -- Checkpoints
    :<|> handleCreateCheckpoint cmdBus repo user
    :<|> handleCommitCheckpoint cmdBus repo user
    :<|> handleRollbackCheckpoint cmdBus repo user
    -- Import/Export
    :<|> handleExport repo user
    :<|> handleImport cmdBus repo user
    -- Absence type management
    :<|> handleCreateAbsenceType cmdBus repo user
    :<|> handleDeleteAbsenceType cmdBus repo user
    :<|> handleSetAbsenceAllowance cmdBus repo user
    -- User management
    :<|> handleListUsers repo user
    :<|> handleCreateUser cmdBus repo user
    :<|> handleDeleteUser cmdBus repo user
    :<|> handleRenameUser cmdBus repo user
    :<|> handleForceDeleteUser cmdBus repo user
    -- Worker entity
    :<|> handleViewWorker repo user
    :<|> handleDeactivateWorker cmdBus repo user
    :<|> handleActivateWorker cmdBus repo user
    :<|> handleDeleteWorker cmdBus repo user
    :<|> handleForceDeleteWorker cmdBus repo user
    -- Hint sessions
    :<|> handleListHints repo user
    :<|> handleAddHint repo user
    :<|> handleRevertHint repo user
    :<|> handleApplyHints repo user
    :<|> handleRebaseHints repo user

-- | Protected server: REST + RPC, both receiving User from AuthProtect.
protectedServer :: ExecuteEnv -> Repository -> User -> Server (RawAPI :<|> RpcAPI)
protectedServer execEnv repo user =
    let cmdBus = busCommands (eeBus execEnv)
    in server execEnv cmdBus repo user :<|> rpcServer execEnv repo user

-- | Combined server: Public + Protected.
fullServer :: ExecuteEnv -> Repository -> Server FullAPI
fullServer execEnv repo =
         handleLogin repo
    :<|> protectedServer execEnv repo

-- -----------------------------------------------------------------
-- Skills / Stations / Shifts (read — no auth guard needed)
-- -----------------------------------------------------------------

handleListSkills :: Repository -> Handler [Skill]
handleListSkills repo = do
    skills <- liftIO $ SW.listSkills repo
    pure [sk | (_, sk) <- skills]

handleListStations :: Repository -> Handler [Station]
handleListStations repo = do
    stations <- liftIO $ SW.listStations repo
    pure [st | (_, st) <- stations]

handleListShifts :: Repository -> Handler [ShiftDef]
handleListShifts repo = liftIO $ repoLoadShifts repo

-- -----------------------------------------------------------------
-- Schedules
-- -----------------------------------------------------------------

handleListSchedules :: Repository -> Handler [T.Text]
handleListSchedules repo = liftIO $ SS.listSchedules repo

handleGetSchedule :: Repository -> String -> Handler Schedule
handleGetSchedule repo name = do
    mSched <- liftIO $ SS.getSchedule repo (T.pack name)
    case mSched of
        Nothing -> throwApiError (NotFound ("Schedule not found: " ++ name))
        Just s  -> pure s

handleDeleteSchedule :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleDeleteSchedule cmdBus repo user name = do
    requireAdmin user
    liftIO $ SS.deleteSchedule repo (T.pack name)
    logRest cmdBus user ("schedule delete " ++ shellQuote name)
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

handleCommitDraft :: TopicBus CommandEvent -> Repository -> User -> Int -> CommitDraftReq -> Handler NoContent
handleCommitDraft cmdBus repo user did req = do
    requireAdmin user
    result <- liftIO $ SD.commitDraft repo did (cmrNote req)
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> do
            logRest cmdBus user ("draft commit " ++ show did)
            pure NoContent

handleDiscardDraft :: TopicBus CommandEvent -> Repository -> User -> Int -> Handler NoContent
handleDiscardDraft cmdBus repo user did = do
    requireAdmin user
    result <- liftIO $ SD.discardDraft repo did
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> do
            logRest cmdBus user ("draft discard " ++ show did)
            pure NoContent

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
        Normal -> pure $ filter (\a -> arWorker a == userIdToWorkerId (userId user)) allPending

handleRequestAbsence :: TopicBus CommandEvent -> Repository -> User -> RequestAbsenceReq -> Handler AbsenceCreatedResp
handleRequestAbsence cmdBus repo user req = do
    requireSelfOrAdmin user (rarWorkerId req)
    result <- liftIO $ SA.requestAbsenceService repo
        (WorkerId (rarWorkerId req))
        (AbsenceTypeId (rarTypeId req))
        (rarFrom req)
        (rarTo req)
    case result of
        Left SA.UnknownAbsenceType -> throwApiError (BadRequest "Unknown absence type")
        Left err -> throwApiError (InternalError (show err))
        Right (AbsenceId aid) -> do
            logRest cmdBus user ("absence request " ++ show (rarWorkerId req) ++ " " ++ show (rarTypeId req) ++ " " ++ show (rarFrom req) ++ " " ++ show (rarTo req))
            pure (AbsenceCreatedResp aid)

handleApproveAbsence :: TopicBus CommandEvent -> Repository -> User -> Int -> Handler NoContent
handleApproveAbsence cmdBus repo user aid = do
    requireAdmin user
    result <- liftIO $ SA.approveAbsenceService repo (AbsenceId aid)
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left SA.AbsenceAllowanceExceeded -> throwApiError (Conflict "Allowance exceeded")
        Left err -> throwApiError (InternalError (show err))
        Right () -> do
            logRest cmdBus user ("absence approve " ++ show aid)
            pure NoContent

handleRejectAbsence :: TopicBus CommandEvent -> Repository -> User -> Int -> Handler NoContent
handleRejectAbsence cmdBus repo user aid = do
    requireAdmin user
    result <- liftIO $ SA.rejectAbsenceService repo (AbsenceId aid)
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left err -> throwApiError (InternalError (show err))
        Right () -> do
            logRest cmdBus user ("absence reject " ++ show aid)
            pure NoContent

-- -----------------------------------------------------------------
-- Config (read)
-- -----------------------------------------------------------------

handleGetConfig :: Repository -> Handler [(String, Double)]
handleGetConfig repo = liftIO $ SCfg.listConfigParams repo

-- -----------------------------------------------------------------
-- Skill CRUD
-- -----------------------------------------------------------------

handleCreateSkill :: TopicBus CommandEvent -> Repository -> User -> CreateSkillReq -> Handler NoContent
handleCreateSkill cmdBus repo user req = do
    requireAdmin user
    result <- liftIO $ SW.addSkill repo (csrName req) (csrDescription req)
    case result of
        Left err -> throwApiError (Conflict err)
        Right () -> do
            logRest cmdBus user ("skill create " ++ shellQuote (T.unpack (csrName req)))
            pure NoContent

handleDeleteSkill :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleDeleteSkill cmdBus repo user name = do
    requireAdmin user
    sid <- resolveSkillName repo name
    result <- liftIO $ SW.safeDeleteSkill repo sid
    case result of
        Right () -> do
            logRest cmdBus user ("skill delete " ++ shellQuote (T.unpack name))
            pure NoContent
        Left refs -> throwError $ err409
            { errBody = encode (toJSON (SkillReferencesResp refs))
            , errHeaders = [("Content-Type", "application/json")]
            }

handleForceDeleteSkill :: ExecuteEnv -> Repository -> User -> Text -> Handler NoContent
handleForceDeleteSkill execEnv repo user name = do
    requireAdmin user
    _ <- resolveSkillName repo name
    _ <- liftIO $ executeCommandText execEnv user ("skill force-delete " ++ shellQuote (T.unpack name))
    pure NoContent

handleRenameSkill :: TopicBus CommandEvent -> Repository -> User -> Text -> RenameSkillReq -> Handler NoContent
handleRenameSkill cmdBus repo user name req = do
    requireAdmin user
    sid <- resolveSkillName repo name
    liftIO $ SW.renameSkill repo sid (rsrName req)
    logRest cmdBus user ("skill rename " ++ shellQuote (T.unpack name) ++ " " ++ shellQuote (T.unpack (rsrName req)))
    pure NoContent

handleListImplications :: Repository -> Handler (Map.Map Text [Text])
handleListImplications repo = do
    skills <- liftIO $ SW.listSkills repo
    implMap <- liftIO $ SW.listSkillImplications repo
    let nameOf sid = case lookup sid skills of
            Just sk -> skillName sk
            Nothing -> T.pack (show sid)
    pure $ Map.fromList
        [ (nameOf sid, map nameOf impls)
        | (sid, impls) <- Map.toList implMap
        ]

handleAddImplication :: TopicBus CommandEvent -> Repository -> User -> Text -> AddImplicationReq -> Handler NoContent
handleAddImplication cmdBus repo user name req = do
    requireAdmin user
    sid <- resolveSkillName repo name
    implSid <- resolveSkillName repo (T.pack (airImpliesSkillName req))
    liftIO $ SW.addSkillImplication repo sid implSid
    logRest cmdBus user ("skill implication " ++ shellQuote (T.unpack name) ++ " " ++ shellQuote (airImpliesSkillName req))
    pure NoContent

handleRemoveImplication :: TopicBus CommandEvent -> Repository -> User -> Text -> Text -> Handler NoContent
handleRemoveImplication cmdBus repo user name impliedName = do
    requireAdmin user
    sid <- resolveSkillName repo name
    impliedSid <- resolveSkillName repo impliedName
    liftIO $ SW.removeSkillImplication repo sid impliedSid
    logRest cmdBus user ("skill remove-implication " ++ shellQuote (T.unpack name) ++ " " ++ shellQuote (T.unpack impliedName))
    pure NoContent

-- -----------------------------------------------------------------
-- Station CRUD
-- -----------------------------------------------------------------

handleCreateStation :: TopicBus CommandEvent -> Repository -> User -> CreateStationReq -> Handler NoContent
handleCreateStation cmdBus repo user req = do
    requireAdmin user
    _sid <- liftIO $ SW.addStation repo (cstrName req) (cstrMinStaff req) (cstrMaxStaff req)
    logRest cmdBus user ("station create " ++ shellQuote (T.unpack (cstrName req)))
    pure NoContent

handleDeleteStation :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleDeleteStation cmdBus repo user name = do
    requireAdmin user
    sid <- resolveStationName repo name
    result <- liftIO $ SW.safeDeleteStation repo sid
    case result of
        Right () -> do
            logRest cmdBus user ("station delete " ++ shellQuote (T.unpack name))
            pure NoContent
        Left refs -> throwError $ err409
            { errBody = encode (toJSON (StationReferencesResp refs))
            , errHeaders = [("Content-Type", "application/json")]
            }

handleForceDeleteStation :: ExecuteEnv -> Repository -> User -> Text -> Handler NoContent
handleForceDeleteStation execEnv repo user name = do
    requireAdmin user
    _ <- resolveStationName repo name
    _ <- liftIO $ executeCommandText execEnv user ("station force-delete " ++ shellQuote (T.unpack name))
    pure NoContent

handleRenameStation :: TopicBus CommandEvent -> Repository -> User -> Text -> RenameStationReq -> Handler NoContent
handleRenameStation cmdBus repo user name req = do
    requireAdmin user
    sid <- resolveStationName repo name
    liftIO $ SW.renameStation repo sid (rstrName req)
    logRest cmdBus user ("station rename " ++ shellQuote (T.unpack name) ++ " " ++ shellQuote (T.unpack (rstrName req)))
    pure NoContent

handleSetStationHours :: TopicBus CommandEvent -> Repository -> User -> Text -> SetStationHoursReq -> Handler NoContent
handleSetStationHours cmdBus repo user name req = do
    requireAdmin user
    sid <- resolveStationName repo name
    liftIO $ SW.setStationHours repo sid (sshrStart req) (sshrEnd req)
    logRest cmdBus user ("station set-hours " ++ shellQuote (T.unpack name) ++ " " ++ show (sshrStart req) ++ " " ++ show (sshrEnd req))
    pure NoContent

handleSetStationClosure :: TopicBus CommandEvent -> Repository -> User -> Text -> SetStationClosureReq -> Handler NoContent
handleSetStationClosure cmdBus repo user name req = do
    requireAdmin user
    sid <- resolveStationName repo name
    liftIO $ SW.closeStationDay repo sid (sscrDay req)
    logRest cmdBus user ("station close-day " ++ shellQuote (T.unpack name) ++ " " ++ show (sscrDay req))
    pure NoContent

-- -----------------------------------------------------------------
-- Shift CRUD
-- -----------------------------------------------------------------

handleCreateShift :: TopicBus CommandEvent -> Repository -> User -> CreateShiftReq -> Handler NoContent
handleCreateShift cmdBus repo user req = do
    requireAdmin user
    liftIO $ repoSaveShift repo (ShiftDef (T.pack (cshrName req)) (cshrStart req) (cshrEnd req))
    logRest cmdBus user ("shift create " ++ shellQuote (cshrName req) ++ " " ++ show (cshrStart req) ++ " " ++ show (cshrEnd req))
    pure NoContent

handleDeleteShift :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleDeleteShift cmdBus repo user name = do
    requireAdmin user
    liftIO $ repoDeleteShift repo (T.pack name)
    logRest cmdBus user ("shift delete " ++ shellQuote name)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker configuration
-- -----------------------------------------------------------------

handleSetWorkerHours :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerHoursReq -> Handler NoContent
handleSetWorkerHours cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setMaxHours repo (WorkerId wid) (fromIntegral (swhrHours req))
    logRest cmdBus user ("worker set-hours " ++ shellQuote wName ++ " " ++ show (swhrHours req))
    pure NoContent

handleSetWorkerOvertime :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerOvertimeReq -> Handler NoContent
handleSetWorkerOvertime cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    _ <- liftIO $ SW.setOvertimeOptIn repo (WorkerId wid) (sworOptIn req)
    logRest cmdBus user ("worker set-overtime " ++ shellQuote wName ++ " " ++ show (sworOptIn req))
    pure NoContent

handleSetWorkerPrefs :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerPrefsReq -> Handler NoContent
handleSetWorkerPrefs cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setStationPreferences repo (WorkerId wid)
        (map StationId (swprStationIds req))
    logRest cmdBus user ("worker set-prefs " ++ shellQuote wName)
    pure NoContent

handleSetWorkerVariety :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerVarietyReq -> Handler NoContent
handleSetWorkerVariety cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setVarietyPreference repo (WorkerId wid) (swvrPrefer req)
    logRest cmdBus user ("worker set-variety " ++ shellQuote wName ++ " " ++ show (swvrPrefer req))
    pure NoContent

handleSetWorkerShiftPrefs :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerShiftPrefsReq -> Handler NoContent
handleSetWorkerShiftPrefs cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setShiftPreferences repo (WorkerId wid) (map T.pack (swsprShifts req))
    logRest cmdBus user ("worker set-shift-pref " ++ shellQuote wName)
    pure NoContent

handleSetWorkerWeekendOnly :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerWeekendOnlyReq -> Handler NoContent
handleSetWorkerWeekendOnly cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setWeekendOnly repo (WorkerId wid) (swwoVal req)
    logRest cmdBus user ("worker set-weekend-only " ++ shellQuote wName ++ " " ++ show (swwoVal req))
    pure NoContent

handleSetWorkerSeniority :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerSeniorityReq -> Handler NoContent
handleSetWorkerSeniority cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setSeniority repo (WorkerId wid) (swsrLevel req)
    logRest cmdBus user ("worker set-seniority " ++ shellQuote wName ++ " " ++ show (swsrLevel req))
    pure NoContent

handleSetWorkerCrossTraining :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerCrossTrainingReq -> Handler NoContent
handleSetWorkerCrossTraining cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    skName <- liftIO $ lookupSkillName repo (SkillId (swctrSkillId req))
    liftIO $ SW.addCrossTraining repo (WorkerId wid) (SkillId (swctrSkillId req))
    logRest cmdBus user ("worker set-cross-training " ++ shellQuote wName ++ " " ++ shellQuote skName)
    pure NoContent

handleSetWorkerEmploymentStatus :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerEmploymentStatusReq -> Handler NoContent
handleSetWorkerEmploymentStatus cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    _ <- liftIO $ SW.setEmploymentStatus repo (WorkerId wid) (swesStatus req)
    logRest cmdBus user ("worker set-status " ++ shellQuote wName ++ " " ++ swesStatus req)
    pure NoContent

handleSetWorkerOvertimeModel :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerOvertimeModelReq -> Handler NoContent
handleSetWorkerOvertimeModel cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setOvertimeModel repo (WorkerId wid) (swomModel req)
    logRest cmdBus user ("worker set-overtime-model " ++ shellQuote wName)
    pure NoContent

handleSetWorkerPayTracking :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerPayTrackingReq -> Handler NoContent
handleSetWorkerPayTracking cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setPayPeriodTracking repo (WorkerId wid) (swptTracking req)
    logRest cmdBus user ("worker set-pay-tracking " ++ shellQuote wName)
    pure NoContent

handleSetWorkerTemp :: TopicBus CommandEvent -> Repository -> User -> Int -> SetWorkerTempReq -> Handler NoContent
handleSetWorkerTemp cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    liftIO $ SW.setTempFlag repo (WorkerId wid) (swtTemp req)
    logRest cmdBus user ("worker set-temp " ++ shellQuote wName ++ " " ++ show (swtTemp req))
    pure NoContent

-- -----------------------------------------------------------------
-- Worker skill grant / revoke
-- -----------------------------------------------------------------

handleGrantWorkerSkill :: TopicBus CommandEvent -> Repository -> User -> Int -> SkillId -> Handler NoContent
handleGrantWorkerSkill cmdBus repo user wid sid = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    skName <- liftIO $ lookupSkillName repo sid
    liftIO $ SW.grantWorkerSkill repo (WorkerId wid) sid
    logRest cmdBus user ("worker grant-skill " ++ shellQuote wName ++ " " ++ shellQuote skName)
    pure NoContent

handleRevokeWorkerSkill :: TopicBus CommandEvent -> Repository -> User -> Int -> SkillId -> Handler NoContent
handleRevokeWorkerSkill cmdBus repo user wid sid = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    skName <- liftIO $ lookupSkillName repo sid
    liftIO $ SW.revokeWorkerSkill repo (WorkerId wid) sid
    logRest cmdBus user ("worker revoke-skill " ++ shellQuote wName ++ " " ++ shellQuote skName)
    pure NoContent

-- -----------------------------------------------------------------
-- Worker pairing
-- -----------------------------------------------------------------

handleAvoidPairing :: TopicBus CommandEvent -> Repository -> User -> Int -> WorkerPairingReq -> Handler NoContent
handleAvoidPairing cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    otherName <- liftIO $ lookupWorkerName repo (WorkerId (wprOtherWorkerId req))
    liftIO $ SW.addAvoidPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    logRest cmdBus user ("worker avoid-pairing " ++ shellQuote wName ++ " " ++ shellQuote otherName)
    pure NoContent

handlePreferPairing :: TopicBus CommandEvent -> Repository -> User -> Int -> WorkerPairingReq -> Handler NoContent
handlePreferPairing cmdBus repo user wid req = do
    requireSelfOrAdmin user wid
    wName <- liftIO $ lookupWorkerName repo (WorkerId wid)
    otherName <- liftIO $ lookupWorkerName repo (WorkerId (wprOtherWorkerId req))
    liftIO $ SW.addPreferPairing repo (WorkerId wid) (WorkerId (wprOtherWorkerId req))
    logRest cmdBus user ("worker prefer-pairing " ++ shellQuote wName ++ " " ++ shellQuote otherName)
    pure NoContent

-- -----------------------------------------------------------------
-- Pins
-- -----------------------------------------------------------------

handleListPins :: Repository -> Handler [PinnedAssignment]
handleListPins repo = liftIO $ SW.listPins repo

handleAddPin :: TopicBus CommandEvent -> Repository -> User -> PinnedAssignment -> Handler NoContent
handleAddPin cmdBus repo user pin = do
    requireAdmin user
    wName <- liftIO $ lookupWorkerName repo (pinWorker pin)
    sName <- liftIO $ lookupStationName repo (pinStation pin)
    liftIO $ SW.addPin repo pin
    logRest cmdBus user ("pin " ++ shellQuote wName ++ " " ++ shellQuote (T.unpack sName))
    pure NoContent

handleRemovePin :: TopicBus CommandEvent -> Repository -> User -> PinnedAssignment -> Handler NoContent
handleRemovePin cmdBus repo user pin = do
    requireAdmin user
    wName <- liftIO $ lookupWorkerName repo (pinWorker pin)
    sName <- liftIO $ lookupStationName repo (pinStation pin)
    liftIO $ SW.removePin repo pin
    logRest cmdBus user ("unpin " ++ shellQuote wName ++ " " ++ shellQuote (T.unpack sName))
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

handleSetConfig :: TopicBus CommandEvent -> Repository -> User -> String -> SetConfigReq -> Handler NoContent
handleSetConfig cmdBus repo user key req = do
    requireAdmin user
    result <- liftIO $ SCfg.setConfigParam repo key (scrValue req)
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown config key: " ++ key))
        Just _  -> do
            logRest cmdBus user ("config set " ++ key ++ " " ++ show (scrValue req))
            pure NoContent

handleApplyPreset :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleApplyPreset cmdBus repo user name = do
    requireAdmin user
    result <- liftIO $ SCfg.applyPreset repo name
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown preset: " ++ name))
        Just _  -> do
            logRest cmdBus user ("config preset " ++ shellQuote name)
            pure NoContent

handleResetConfig :: TopicBus CommandEvent -> Repository -> User -> Handler NoContent
handleResetConfig cmdBus repo user = do
    requireAdmin user
    liftIO $ SCfg.saveConfig repo =<< SCfg.loadConfig repo
    logRest cmdBus user "config reset"
    pure NoContent

handleSetPayPeriod :: TopicBus CommandEvent -> Repository -> User -> SetPayPeriodReq -> Handler NoContent
handleSetPayPeriod cmdBus repo user req = do
    requireAdmin user
    case parsePayPeriodType (sprType req) of
        Nothing -> throwApiError (BadRequest ("Unknown pay period type: " ++ sprType req))
        Just pt -> do
            liftIO $ SCfg.savePayPeriodConfig repo
                (PayPeriodConfig pt (sprAnchorDate req))
            logRest cmdBus user ("config set-pay-period " ++ shellQuote (sprType req))
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

handleCreateCheckpoint :: TopicBus CommandEvent -> Repository -> User -> CreateCheckpointReq -> Handler NoContent
handleCreateCheckpoint cmdBus repo user req = do
    requireAdmin user
    liftIO $ repoSavepoint repo (ccrName req)
    logRest cmdBus user ("checkpoint create " ++ shellQuote (T.unpack (ccrName req)))
    pure NoContent

handleCommitCheckpoint :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleCommitCheckpoint cmdBus repo user name = do
    requireAdmin user
    liftIO $ repoRelease repo (T.pack name)
    logRest cmdBus user ("checkpoint commit " ++ shellQuote name)
    pure NoContent

handleRollbackCheckpoint :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleRollbackCheckpoint cmdBus repo user name = do
    requireAdmin user
    liftIO $ repoRollbackTo repo (T.pack name)
    logRest cmdBus user ("checkpoint rollback " ++ shellQuote name)
    pure NoContent

-- -----------------------------------------------------------------
-- Import / Export
-- -----------------------------------------------------------------

handleExport :: Repository -> User -> Handler ExportResp
handleExport repo user = do
    requireAdmin user
    dat <- liftIO $ Exp.gatherExport repo Nothing
    pure (ExportResp dat)

handleImport :: TopicBus CommandEvent -> Repository -> User -> ImportReq -> Handler ImportResp
handleImport cmdBus repo user req = do
    requireAdmin user
    msgs <- liftIO $ Exp.applyImport repo (irData req)
    logRest cmdBus user "import data"
    pure (ImportResp msgs)

-- -----------------------------------------------------------------
-- Absence type management
-- -----------------------------------------------------------------

handleCreateAbsenceType :: TopicBus CommandEvent -> Repository -> User -> CreateAbsenceTypeReq -> Handler NoContent
handleCreateAbsenceType cmdBus repo user req = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let nextTid = if Map.null (acTypes ctx)
                  then 1
                  else let AbsenceTypeId maxId = maximum (Map.keys (acTypes ctx))
                       in maxId + 1
        newType = AbsenceType (catrName req) (catrCountsAgainstAllowance req)
        ctx' = ctx { acTypes = Map.insert (AbsenceTypeId nextTid) newType (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    logRest cmdBus user ("absence-type create " ++ shellQuote (T.unpack (catrName req)))
    pure NoContent

handleDeleteAbsenceType :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleDeleteAbsenceType cmdBus repo user name = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let matches = [ tid | (tid, at) <- Map.toList (acTypes ctx)
                  , T.toLower (atName at) == T.toLower name ]
    case matches of
        [atId] -> do
            let ctx' = ctx { acTypes = Map.delete atId (acTypes ctx) }
            liftIO $ repoSaveAbsenceCtx repo ctx'
            logRest cmdBus user ("absence-type delete " ++ shellQuote (T.unpack name))
            pure NoContent
        [] -> throwError err404
        _  -> throwError err409

handleSetAbsenceAllowance :: TopicBus CommandEvent -> Repository -> User -> Text -> SetAbsenceAllowanceReq -> Handler NoContent
handleSetAbsenceAllowance cmdBus repo user name req = do
    requireAdmin user
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let matches = [ tid | (tid, at) <- Map.toList (acTypes ctx)
                  , T.toLower (atName at) == T.toLower name ]
    case matches of
        [atId] -> do
            let key = (WorkerId (saarWorkerId req), atId)
                ctx' = ctx { acYearlyAllowance = Map.insert key (saarAllowance req) (acYearlyAllowance ctx) }
            liftIO $ repoSaveAbsenceCtx repo ctx'
            logRest cmdBus user ("absence set-allowance " ++ shellQuote (T.unpack name) ++ " " ++ show (saarWorkerId req) ++ " " ++ show (saarAllowance req))
            pure NoContent
        [] -> throwError err404
        _  -> throwError err409

-- -----------------------------------------------------------------
-- User management
-- -----------------------------------------------------------------

handleListUsers :: Repository -> User -> Handler [User]
handleListUsers repo user = do
    requireAdmin user
    liftIO $ repoListUsers repo

handleCreateUser :: TopicBus CommandEvent -> Repository -> User -> CreateUserReq -> Handler NoContent
handleCreateUser cmdBus repo user req = do
    requireAdmin user
    result <- liftIO $ SAuth.register repo
        (curUsername req) (curPassword req) (curRole req) (curNoWorker req)
    case result of
        Left SAuth.UsernameTaken -> throwApiError (Conflict "Username already taken")
        Left err -> throwApiError (InternalError (show err))
        Right _ -> do
            logRest cmdBus user ("user create " ++ shellQuote (T.unpack (curUsername req)))
            pure NoContent

handleDeleteUser :: TopicBus CommandEvent -> Repository -> User -> String -> Handler NoContent
handleDeleteUser cmdBus repo user uname = do
    requireAdmin user
    mUser <- liftIO $ repoGetUserByName repo (T.pack uname)
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ uname))
        Just u  -> do
            r <- liftIO $ SU.safeDeleteUser repo (userId u)
            case r of
                Right () -> do
                    logRest cmdBus user ("user delete " ++ shellQuote uname)
                    pure NoContent
                Left err -> throwApiError (Conflict err)

handleRenameUser :: TopicBus CommandEvent -> Repository -> User -> Int -> RenameUserReq -> Handler NoContent
handleRenameUser cmdBus repo user uid req = do
    requireAdmin user
    mUser <- liftIO $ repoGetUser repo (UserId uid)
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ show uid))
        Just u  -> do
            let Username old = userName u
            r <- liftIO $ SU.renameUser repo old (rurNewName req)
            case r of
                Right () -> do
                    logRest cmdBus user
                        ("user rename " ++ shellQuote (T.unpack old) ++ " "
                         ++ shellQuote (T.unpack (rurNewName req)))
                    pure NoContent
                Left err -> throwApiError (Conflict err)

handleForceDeleteUser :: TopicBus CommandEvent -> Repository -> User -> Int -> Handler NoContent
handleForceDeleteUser cmdBus repo user uid = do
    requireAdmin user
    mUser <- liftIO $ repoGetUser repo (UserId uid)
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ show uid))
        Just u  -> do
            liftIO $ SU.forceDeleteUser repo (userId u)
            logRest cmdBus user ("user force-delete " ++ show uid)
            pure NoContent

-- -----------------------------------------------------------------
-- Worker entity (view, deactivate, activate, delete)
-- -----------------------------------------------------------------

-- | Resolve a worker by name, mapping CLI errors onto Servant 4xx codes.
resolveWorkerName :: Repository -> Text -> Handler WorkerId
resolveWorkerName repo name = do
    r <- liftIO $ SW.resolveWorkerByName repo name
    case r of
        Right (wid, _) -> pure wid
        Left (SW.WorkerNotFound n) -> throwApiError (NotFound ("User not found: " ++ n))
        Left (SW.NotAWorker n)     -> throwApiError (NotFound ("User '" ++ n ++ "' is not a worker"))

handleViewWorker :: Repository -> User -> Text -> Handler WorkerProfileResp
handleViewWorker repo user name = do
    requireAdmin user
    wid <- resolveWorkerName repo name
    mp <- liftIO $ SW.viewWorker repo wid
    case mp of
        Nothing -> throwApiError (NotFound ("No profile for worker '" ++ T.unpack name ++ "'"))
        Just p  -> pure (toProfileResp p)

handleDeactivateWorker :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler DeactivateResultResp
handleDeactivateWorker cmdBus repo user name = do
    requireAdmin user
    wid <- resolveWorkerName repo name
    today <- liftIO $ utctDay <$> getCurrentTime
    r <- liftIO $ SW.safeDeactivateWorker repo wid today
    case r of
        Right (SW.DeactivateResult pn dn cn) -> do
            logRest cmdBus user ("worker deactivate " ++ shellQuote (T.unpack name))
            pure (DeactivateResultResp pn dn cn)
        Left err -> throwApiError (Conflict err)

handleActivateWorker :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleActivateWorker cmdBus repo user name = do
    requireAdmin user
    wid <- resolveWorkerName repo name
    r <- liftIO $ SW.activateWorker repo wid
    case r of
        Right () -> do
            logRest cmdBus user ("worker activate " ++ shellQuote (T.unpack name))
            pure NoContent
        Left err -> throwApiError (Conflict err)

handleDeleteWorker :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleDeleteWorker cmdBus repo user name = do
    requireAdmin user
    wid <- resolveWorkerName repo name
    r <- liftIO $ SW.safeDeleteWorker repo wid
    case r of
        Right () -> do
            logRest cmdBus user ("worker delete " ++ shellQuote (T.unpack name))
            pure NoContent
        Left refs ->
            -- 409 Conflict with a body listing references (configuration vs. schedule).
            throwConflictWithBody (toWorkerRefsResp refs)

handleForceDeleteWorker :: TopicBus CommandEvent -> Repository -> User -> Text -> Handler NoContent
handleForceDeleteWorker cmdBus repo user name = do
    requireAdmin user
    wid <- resolveWorkerName repo name
    liftIO $ SW.forceDeleteWorker repo wid
    logRest cmdBus user ("worker force-delete " ++ shellQuote (T.unpack name))
    pure NoContent

-- -----------------------------------------------------------------
-- Conversion helpers
-- -----------------------------------------------------------------

toProfileResp :: SW.WorkerProfile -> WorkerProfileResp
toProfileResp p = WorkerProfileResp
    { wprName              = SW.wpName p
    , wprUserId            = SW.wpUserId p
    , wprWorkerId          = SW.wpWorkerId p
    , wprRole              = SW.wpRole p
    , wprStatus            = workerStatusToText (SW.wpStatus p)
    , wprDeactivatedAt     = T.pack . show <$> SW.wpDeactivatedAt p
    , wprOvertimeModel     = case SW.wpOvertimeModel p of
                                OTEligible    -> "eligible"
                                OTManualOnly  -> "manual-only"
                                OTExempt      -> "exempt"
    , wprPayPeriodTracking = case SW.wpPayPeriodTracking p of
                                PPStandard -> "standard"
                                PPExempt   -> "exempt"
    , wprIsTemp            = SW.wpIsTemp p
    , wprMaxPeriodHours    = (\dt -> round (toRational dt / 3600)) <$> SW.wpMaxPeriodHours p
    , wprOvertimeOptIn     = SW.wpOvertimeOptIn p
    , wprWeekendOnly       = SW.wpWeekendOnly p
    , wprPrefersVariety    = SW.wpPrefersVariety p
    , wprSeniority         = SW.wpSeniority p
    , wprSkills            = SW.wpSkills p
    , wprStationPrefs      = SW.wpStationPrefs p
    , wprShiftPrefs        = SW.wpShiftPrefs p
    , wprCrossTraining     = SW.wpCrossTraining p
    , wprAvoidPairing      = SW.wpAvoidPairing p
    , wprPreferPairing     = SW.wpPreferPairing p
    }

toWorkerRefsResp :: SW.WorkerReferences -> WorkerReferencesResp
toWorkerRefsResp r = WorkerReferencesResp
    { wrrConfiguration = filter (not . T.null)
        [ countTxt "skills" (SW.wrSkills r)
        , flagTxt  "employment"      (SW.wrEmployment r)
        , flagTxt  "max-period hours" (SW.wrHours r)
        , flagTxt  "overtime opt-in"  (SW.wrOvertimeOptIn r)
        , countTxt "station prefs"   (SW.wrStationPrefs r)
        , flagTxt  "prefers variety"  (SW.wrPrefersVariety r)
        , countTxt "shift prefs"     (SW.wrShiftPrefs r)
        , flagTxt  "weekend-only flag" (SW.wrWeekendOnly r)
        , flagTxt  "seniority"        (SW.wrSeniority r)
        , countTxt "avoid-pairing"   (SW.wrAvoidPairing r)
        , countTxt "prefer-pairing"  (SW.wrPreferPairing r)
        , countTxt "cross-training"  (SW.wrCrossTraining r)
        ]
    , wrrSchedule = filter (not . T.null)
        [ countTxt "pinned"   (SW.wrPinned r)
        , countTxt "calendar" (SW.wrCalendar r)
        , countTxt "draft"    (SW.wrDraft r)
        , countTxt "schedule" (SW.wrSchedule r)
        , countTxt "absence"  (SW.wrAbsence r)
        , countTxt "yearly allowances" (SW.wrAllowances r)
        ]
    }
  where
    countTxt _ 0 = ""
    countTxt n k = T.pack (show k ++ " " ++ n)
    flagTxt _ False = ""
    flagTxt n True  = T.pack ("yes " ++ n)

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
