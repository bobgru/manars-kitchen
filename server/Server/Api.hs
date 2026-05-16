{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server.Api
    ( API
    , RawAPI
    , PublicAPI
    , FullAPI
    , api
    , fullApi
    ) where

import Data.Map.Strict (Map)
import Data.Proxy (Proxy(..))
import Data.Text (Text)
import Data.Time (Day)
import Servant.API
import Servant.Server.Experimental.Auth (AuthServerData)

import Auth.Types (User)
import Domain.Types (SkillId, Schedule, Station)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest)
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment)
import Repo.Types (DraftInfo, CalendarCommit, AuditEntry)
import Server.Json
import Server.Auth (LoginReq, LoginResp)
import Server.Rpc (RpcAPI)

-- | Map the AuthProtect tag to the User type.
type instance AuthServerData (AuthProtect "session") = User

-- | Public endpoints (no auth required).
type PublicAPI =
         "api" :> "login" :> ReqBody '[JSON] LoginReq :> Post '[JSON] LoginResp

-- | The raw REST API (without auth combinator — used inside ProtectedAPI).
type RawAPI =
    -- Logout (requires auth, placed here since it's under the protected block)
         "api" :> "logout" :> PostNoContent

    -- Stations (read)
    :<|> "api" :> "stations" :> Get '[JSON] [Station]
    -- Shifts (read)
    :<|> "api" :> "shifts" :> Get '[JSON] [ShiftDef]
    -- Schedules
    :<|> "api" :> "schedules" :> Get '[JSON] [Text]
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
    :<|> "api" :> "skills" :> Get '[JSON] [Skill]
    :<|> "api" :> "skills" :> ReqBody '[JSON] CreateSkillReq :> PostNoContent
    :<|> "api" :> "skills" :> Capture "name" Text :> DeleteNoContent
    :<|> "api" :> "skills" :> Capture "name" Text :> "force" :> DeleteNoContent
    :<|> "api" :> "skills" :> Capture "name" Text :> ReqBody '[JSON] RenameSkillReq :> PutNoContent
    -- Skill implications
    :<|> "api" :> "skills" :> "implications" :> Get '[JSON] (Map Text [Text])
    :<|> "api" :> "skills" :> Capture "name" Text :> "implications"
         :> ReqBody '[JSON] AddImplicationReq :> PostNoContent
    :<|> "api" :> "skills" :> Capture "name" Text :> "implications"
         :> Capture "impliedName" Text :> DeleteNoContent

    -- -----------------------------------------------------------------
    -- Station CRUD
    -- -----------------------------------------------------------------
    :<|> "api" :> "stations" :> ReqBody '[JSON] CreateStationReq :> PostNoContent
    :<|> "api" :> "stations" :> Capture "name" Text :> DeleteNoContent
    :<|> "api" :> "stations" :> Capture "name" Text :> "force" :> DeleteNoContent
    :<|> "api" :> "stations" :> Capture "name" Text
         :> ReqBody '[JSON] RenameStationReq :> PutNoContent
    :<|> "api" :> "stations" :> Capture "name" Text :> "hours"
         :> ReqBody '[JSON] SetStationHoursReq :> PutNoContent
    :<|> "api" :> "stations" :> Capture "name" Text :> "closure"
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
    :<|> "api" :> "workers" :> Capture "id" Int :> "skills" :> Capture "skillId" SkillId
         :> PostNoContent
    :<|> "api" :> "workers" :> Capture "id" Int :> "skills" :> Capture "skillId" SkillId
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
    :<|> "api" :> "absence-types" :> Capture "name" Text :> DeleteNoContent
    :<|> "api" :> "absence-types" :> Capture "name" Text :> "allowance"
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

-- | The old API type alias (for backward compat in type signatures)
type API = RawAPI

-- | Combined API: Public + Protected (REST + RPC)
type FullAPI = PublicAPI
          :<|> AuthProtect "session" :> (RawAPI :<|> RpcAPI)

api :: Proxy API
api = Proxy

fullApi :: Proxy FullAPI
fullApi = Proxy
