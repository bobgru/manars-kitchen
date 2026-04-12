module Server.Handlers
    ( server
    ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.Set as Set
import Data.Time (Day)
import Servant

import Domain.Types (WorkerId(..), StationId(..), AbsenceId(..), AbsenceTypeId(..), SkillId, Schedule)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest)
import Repo.Types (Repository(..), DraftInfo, CalendarCommit)
import qualified Service.Worker as SW
import qualified Service.Schedule as SS
import qualified Service.Draft as SD
import qualified Service.Calendar as SC
import qualified Service.Absence as SA
import qualified Service.Config as SCfg
import Server.Api (API)
import Server.Json
import Server.Error

server :: Repository -> Server API
server repo =
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
-- Config
-- -----------------------------------------------------------------

handleGetConfig :: Repository -> Handler [(String, Double)]
handleGetConfig repo = liftIO $ SCfg.listConfigParams repo
