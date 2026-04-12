{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Server.Api
    ( API
    , api
    ) where

import Data.Proxy (Proxy(..))
import Data.Time (Day)
import Servant.API

import Domain.Types (SkillId, Schedule)
import Domain.Skill (Skill)
import Domain.Shift (ShiftDef)
import Domain.Scheduler (ScheduleResult)
import Domain.Absence (AbsenceRequest)
import Repo.Types (DraftInfo, CalendarCommit)
import Server.Json

type API =
    -- Skills
         "api" :> "skills" :> Get '[JSON] [(SkillId, Skill)]
    -- Stations
    :<|> "api" :> "stations" :> Get '[JSON] [(Int, String)]
    -- Shifts
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
    -- Calendar
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
    -- Config
    :<|> "api" :> "config" :> Get '[JSON] [(String, Double)]

api :: Proxy API
api = Proxy
