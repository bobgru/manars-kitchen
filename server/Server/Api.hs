{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Server.Api
    ( API
    , FullAPI
    , api
    , fullApi
    ) where

import Data.Proxy (Proxy(..))
import Data.Time (Day)
import Servant.API

import Auth.Types (User)
import Domain.Types (SkillId, Schedule)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest)
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment)
import Repo.Types (DraftInfo, CalendarCommit, AuditEntry)
import Server.Json
import Server.Rpc (RpcAPI)

type API =
    -- Skills (read)
         "api" :> "skills" :> Get '[JSON] [(SkillId, Skill)]
    -- Stations (read)
    :<|> "api" :> "stations" :> Get '[JSON] [(Int, String)]
    -- Shifts (read)
    :<|> "api" :> "shifts" :> Get '[JSON] [ShiftDef]
    -- Schedules
    :<|> "api" :> "schedules" :> Get '[JSON] [String]
    :<|> "api" :> "schedules" :> Capture "name" String :> Get '[JSON] Schedule
    :<|> "api" :> "schedules" :> Capture "name" String :> DeleteNoContent
    -- Drafts
    :<|> "api" :> "drafts" :> Get '[JSON] [DraftInfo]
    :<|> "api" :> "drafts" :> ReqBody '[JSON] CreateDraftReq :> Post '[JSON] DraftCreatedResp
    :<|> "api" :> "drafts" :> Capture "id" Int :> Get '[JSON] DraftInfo
    :<|> "api" :> "drafts" :> Capture "id" Int :> "generate"
         :> ReqBody '[JSON] GenerateDraftReq :> Post '[JSON] ScheduleResult
    :<|> "api" :> "drafts" :> Capture "id" Int :> "commit"
         :> ReqBody '[JSON] CommitDraftReq :> PostNoContent
    :<|> "api" :> "drafts" :> Capture "id" Int :> DeleteNoContent
    -- Calendar (read)
    :<|> "api" :> "calendar" :> QueryParam "from" Day :> QueryParam "to" Day
         :> Get '[JSON] Schedule
    :<|> "api" :> "calendar" :> "history" :> Get '[JSON] [CalendarCommit]
    :<|> "api" :> "calendar" :> "history" :> Capture "id" Int :> Get '[JSON] Schedule
    -- Absences
    :<|> "api" :> "absences" :> "pending" :> Get '[JSON] [AbsenceRequest]
    :<|> "api" :> "absences" :> ReqBody '[JSON] RequestAbsenceReq
         :> Post '[JSON] AbsenceCreatedResp
    :<|> "api" :> "absences" :> Capture "id" Int :> "approve" :> PostNoContent
    :<|> "api" :> "absences" :> Capture "id" Int :> "reject" :> PostNoContent
    -- Config (read)
    :<|> "api" :> "config" :> Get '[JSON] [(String, Double)]

    -- -----------------------------------------------------------------
    -- Skill CRUD
    -- -----------------------------------------------------------------
    :<|> "api" :> "skills" :> ReqBody '[JSON] CreateSkillReq :> PostNoContent
    :<|> "api" :> "skills" :> Capture "id" Int :> DeleteNoContent

    -- -----------------------------------------------------------------
    -- Station CRUD
    -- -----------------------------------------------------------------
    :<|> "api" :> "stations" :> ReqBody '[JSON] CreateStationReq :> PostNoContent
    :<|> "api" :> "stations" :> Capture "id" Int :> DeleteNoContent
    :<|> "api" :> "stations" :> Capture "id" Int :> "hours"
         :> ReqBody '[JSON] SetStationHoursReq :> PutNoContent
    :<|> "api" :> "stations" :> Capture "id" Int :> "closure"
         :> ReqBody '[JSON] SetStationClosureReq :> PutNoContent

    -- -----------------------------------------------------------------
    -- Shift CRUD
    -- -----------------------------------------------------------------
    :<|> "api" :> "shifts" :> ReqBody '[JSON] CreateShiftReq :> PostNoContent
    :<|> "api" :> "shifts" :> Capture "name" String :> DeleteNoContent

    -- -----------------------------------------------------------------
    -- Worker configuration
    -- -----------------------------------------------------------------
    :<|> "api" :> "workers" :> Capture "id" Int :> "hours"
         :> ReqBody '[JSON] SetWorkerHoursReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "overtime"
         :> ReqBody '[JSON] SetWorkerOvertimeReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "prefs"
         :> ReqBody '[JSON] SetWorkerPrefsReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "variety"
         :> ReqBody '[JSON] SetWorkerVarietyReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "shift-prefs"
         :> ReqBody '[JSON] SetWorkerShiftPrefsReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "weekend-only"
         :> ReqBody '[JSON] SetWorkerWeekendOnlyReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "seniority"
         :> ReqBody '[JSON] SetWorkerSeniorityReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "cross-training"
         :> ReqBody '[JSON] SetWorkerCrossTrainingReq :> PostNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "employment-status"
         :> ReqBody '[JSON] SetWorkerEmploymentStatusReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "overtime-model"
         :> ReqBody '[JSON] SetWorkerOvertimeModelReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "pay-tracking"
         :> ReqBody '[JSON] SetWorkerPayTrackingReq :> PutNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "temp"
         :> ReqBody '[JSON] SetWorkerTempReq :> PutNoContent

    -- Worker skill grant/revoke
    :<|> "api" :> "workers" :> Capture "id" Int :> "skills" :> Capture "skillId" Int
         :> PostNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "skills" :> Capture "skillId" Int
         :> DeleteNoContent

    -- Worker pairing
    :<|> "api" :> "workers" :> Capture "id" Int :> "avoid-pairing"
         :> ReqBody '[JSON] WorkerPairingReq :> PostNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "prefer-pairing"
         :> ReqBody '[JSON] WorkerPairingReq :> PostNoContent

    -- -----------------------------------------------------------------
    -- Pins
    -- -----------------------------------------------------------------
    :<|> "api" :> "pins" :> Get '[JSON] [PinnedAssignment]
    :<|> "api" :> "pins" :> ReqBody '[JSON] PinnedAssignment :> PostNoContent
    :<|> "api" :> "pins" :> ReqBody '[JSON] PinnedAssignment :> DeleteNoContent

    -- -----------------------------------------------------------------
    -- Calendar mutations
    -- -----------------------------------------------------------------
    :<|> "api" :> "calendar" :> "unfreeze"
         :> ReqBody '[JSON] UnfreezeReq :> PostNoContent
    :<|> "api" :> "calendar" :> "freeze-status" :> Get '[JSON] FreezeStatusResp

    -- -----------------------------------------------------------------
    -- Config writes
    -- -----------------------------------------------------------------
    :<|> "api" :> "config" :> Capture "key" String
         :> ReqBody '[JSON] SetConfigReq :> PutNoContent
    :<|> "api" :> "config" :> "presets" :> Capture "name" String :> PostNoContent
    :<|> "api" :> "config" :> "reset" :> PostNoContent
    :<|> "api" :> "config" :> "pay-period"
         :> ReqBody '[JSON] SetPayPeriodReq :> PutNoContent

    -- -----------------------------------------------------------------
    -- Audit log
    -- -----------------------------------------------------------------
    :<|> "api" :> "audit" :> Get '[JSON] [AuditEntry]

    -- -----------------------------------------------------------------
    -- Checkpoints
    -- -----------------------------------------------------------------
    :<|> "api" :> "checkpoints" :> ReqBody '[JSON] CreateCheckpointReq :> PostNoContent
    :<|> "api" :> "checkpoints" :> Capture "name" String :> "commit" :> PostNoContent
    :<|> "api" :> "checkpoints" :> Capture "name" String :> "rollback" :> PostNoContent

    -- -----------------------------------------------------------------
    -- Import / Export
    -- -----------------------------------------------------------------
    :<|> "api" :> "export" :> Get '[JSON] ExportResp
    :<|> "api" :> "import" :> ReqBody '[JSON] ImportReq :> Post '[JSON] ImportResp

    -- -----------------------------------------------------------------
    -- Absence type management
    -- -----------------------------------------------------------------
    :<|> "api" :> "absence-types" :> ReqBody '[JSON] CreateAbsenceTypeReq :> PostNoContent
    :<|> "api" :> "absence-types" :> Capture "id" Int :> DeleteNoContent
    :<|> "api" :> "absence-types" :> Capture "id" Int :> "allowance"
         :> ReqBody '[JSON] SetAbsenceAllowanceReq :> PutNoContent

    -- -----------------------------------------------------------------
    -- User management
    -- -----------------------------------------------------------------
    :<|> "api" :> "users" :> Get '[JSON] [User]
    :<|> "api" :> "users" :> ReqBody '[JSON] CreateUserReq :> PostNoContent
    :<|> "api" :> "users" :> Capture "username" String :> DeleteNoContent

    -- -----------------------------------------------------------------
    -- Hint sessions
    -- -----------------------------------------------------------------
    :<|> "api" :> "hints" :> QueryParam "sessionId" Int :> QueryParam "draftId" Int
         :> Get '[JSON] [Hint]
    :<|> "api" :> "hints" :> ReqBody '[JSON] AddHintReq :> Post '[JSON] [Hint]
    :<|> "api" :> "hints" :> "revert" :> ReqBody '[JSON] HintSessionRef :> Post '[JSON] [Hint]
    :<|> "api" :> "hints" :> "apply" :> ReqBody '[JSON] HintSessionRef :> PostNoContent
    :<|> "api" :> "hints" :> "rebase" :> ReqBody '[JSON] HintSessionRef
         :> Post '[JSON] RebaseResultResp

-- | Combined API: REST + RPC
type FullAPI = API :<|> RpcAPI

api :: Proxy API
api = Proxy

fullApi :: Proxy FullAPI
fullApi = Proxy
