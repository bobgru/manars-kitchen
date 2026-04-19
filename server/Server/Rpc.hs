{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Server.Rpc
    ( RpcAPI
    , rpcApi
    , rpcServer
    , sessionMiddleware
      -- * RPC request/response types
    , RpcOk(..)
    , RpcEmpty(..)
    , RpcSkillId(..)
    , RpcStationId(..)
    , RpcStationHours(..)
    , SetStationClosureReq'(..)
    , RpcShiftName(..)
    , RpcWorkerHours(..)
    , RpcWorkerOvertime(..)
    , RpcWorkerPrefs(..)
    , RpcWorkerVariety(..)
    , RpcWorkerShiftPrefs(..)
    , RpcWorkerWeekendOnly(..)
    , RpcWorkerSeniority(..)
    , RpcWorkerCrossTraining(..)
    , RpcWorkerEmploymentStatus(..)
    , RpcWorkerOvertimeModel(..)
    , RpcWorkerPayTracking(..)
    , RpcWorkerTemp(..)
    , RpcWorkerSkill(..)
    , RpcWorkerPairing(..)
    , RpcDraftId(..)
    , RpcDraftGenerate(..)
    , RpcDraftCommit(..)
    , RpcScheduleName(..)
    , RpcDateRange(..)
    , RpcConfigSet(..)
    , RpcPresetName(..)
    , RpcCheckpointName(..)
    , RpcAbsenceTypeId(..)
    , RpcSetAllowance(..)
    , RpcAbsenceId(..)
    , RpcUsername(..)
    , RpcSessionCreate(..)
    , RpcSessionResp(..)
    , ExecuteReq(..)
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:), (.:?), object, withObject)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day, dayOfWeek)
import Network.Wai (Middleware, requestHeaders)
import Servant
import Text.Read (readMaybe)

import Auth.Types (UserId(..), User(..), Username(..))
import Domain.Skill (Skill)
import Domain.Types (WorkerId(..), StationId(..), SkillId(..), AbsenceId(..), AbsenceTypeId(..), Schedule)
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment(..))
import Domain.Shift (ShiftDef(..))
import Domain.Absence (AbsenceType(..), AbsenceContext(..), AbsenceRequest)
import Domain.PayPeriod (parsePayPeriodType, PayPeriodConfig(..))
import Domain.Scheduler (ScheduleResult)
import Domain.Worker (OvertimeModel, PayPeriodTracking)
import Repo.Types
    ( Repository(..), DraftInfo, CalendarCommit, AuditEntry(..)
    , SessionId(..), HintSessionRecord(..)
    )
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
import Server.Json
import Server.Error
import Service.PubSub (TopicBus, CommandEvent, Source(..), AppBus(..), publishCommand, publishCommandWithClient)
import CLI.Commands (shellQuote)
import Server.Execute (ExecuteEnv(..), executeCommandText)

-- -----------------------------------------------------------------
-- RPC API type
-- -----------------------------------------------------------------

-- | All RPC endpoints are POST under /rpc/<group>/<operation>.
-- Request/response is JSON; the body carries all command arguments.
type RpcAPI =
    -- Skill CRUD
         "rpc" :> "skill" :> "create" :> ReqBody '[JSON] CreateSkillReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "skill" :> "delete" :> ReqBody '[JSON] RpcSkillId :> Post '[JSON] RpcOk
    :<|> "rpc" :> "skill" :> "rename" :> Capture "id" Int :> ReqBody '[JSON] RenameSkillReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "skill" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [(SkillId, Skill)]
    -- Station CRUD
    :<|> "rpc" :> "station" :> "create" :> ReqBody '[JSON] CreateStationReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "station" :> "delete" :> ReqBody '[JSON] RpcStationId :> Post '[JSON] RpcOk
    :<|> "rpc" :> "station" :> "set-hours" :> ReqBody '[JSON] RpcStationHours :> Post '[JSON] RpcOk
    :<|> "rpc" :> "station" :> "close-day" :> ReqBody '[JSON] SetStationClosureReq' :> Post '[JSON] RpcOk
    :<|> "rpc" :> "station" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [(Int, String)]
    -- Shift CRUD
    :<|> "rpc" :> "shift" :> "create" :> ReqBody '[JSON] CreateShiftReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "shift" :> "delete" :> ReqBody '[JSON] RpcShiftName :> Post '[JSON] RpcOk
    :<|> "rpc" :> "shift" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [ShiftDef]
    -- Worker configuration
    :<|> "rpc" :> "worker" :> "set-hours" :> ReqBody '[JSON] RpcWorkerHours :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-overtime" :> ReqBody '[JSON] RpcWorkerOvertime :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-prefs" :> ReqBody '[JSON] RpcWorkerPrefs :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-variety" :> ReqBody '[JSON] RpcWorkerVariety :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-shift-prefs" :> ReqBody '[JSON] RpcWorkerShiftPrefs :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-weekend-only" :> ReqBody '[JSON] RpcWorkerWeekendOnly :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-seniority" :> ReqBody '[JSON] RpcWorkerSeniority :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "add-cross-training" :> ReqBody '[JSON] RpcWorkerCrossTraining :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-employment-status" :> ReqBody '[JSON] RpcWorkerEmploymentStatus :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-overtime-model" :> ReqBody '[JSON] RpcWorkerOvertimeModel :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-pay-tracking" :> ReqBody '[JSON] RpcWorkerPayTracking :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "set-temp" :> ReqBody '[JSON] RpcWorkerTemp :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "grant-skill" :> ReqBody '[JSON] RpcWorkerSkill :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "revoke-skill" :> ReqBody '[JSON] RpcWorkerSkill :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "avoid-pairing" :> ReqBody '[JSON] RpcWorkerPairing :> Post '[JSON] RpcOk
    :<|> "rpc" :> "worker" :> "prefer-pairing" :> ReqBody '[JSON] RpcWorkerPairing :> Post '[JSON] RpcOk
    -- Pin management
    :<|> "rpc" :> "pin" :> "add" :> ReqBody '[JSON] PinnedAssignment :> Post '[JSON] RpcOk
    :<|> "rpc" :> "pin" :> "remove" :> ReqBody '[JSON] PinnedAssignment :> Post '[JSON] RpcOk
    :<|> "rpc" :> "pin" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [PinnedAssignment]
    -- Draft operations
    :<|> "rpc" :> "draft" :> "create" :> ReqBody '[JSON] CreateDraftReq :> Post '[JSON] DraftCreatedResp
    :<|> "rpc" :> "draft" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [DraftInfo]
    :<|> "rpc" :> "draft" :> "view" :> ReqBody '[JSON] RpcDraftId :> Post '[JSON] DraftInfo
    :<|> "rpc" :> "draft" :> "generate" :> ReqBody '[JSON] RpcDraftGenerate :> Post '[JSON] ScheduleResult
    :<|> "rpc" :> "draft" :> "commit" :> ReqBody '[JSON] RpcDraftCommit :> Post '[JSON] RpcOk
    :<|> "rpc" :> "draft" :> "discard" :> ReqBody '[JSON] RpcDraftId :> Post '[JSON] RpcOk
    -- Schedule operations
    :<|> "rpc" :> "schedule" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [String]
    :<|> "rpc" :> "schedule" :> "view" :> ReqBody '[JSON] RpcScheduleName :> Post '[JSON] Schedule
    :<|> "rpc" :> "schedule" :> "delete" :> ReqBody '[JSON] RpcScheduleName :> Post '[JSON] RpcOk
    -- Calendar operations
    :<|> "rpc" :> "calendar" :> "view" :> ReqBody '[JSON] RpcDateRange :> Post '[JSON] Schedule
    :<|> "rpc" :> "calendar" :> "history" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [CalendarCommit]
    :<|> "rpc" :> "calendar" :> "unfreeze" :> ReqBody '[JSON] UnfreezeReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "calendar" :> "freeze-status" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] FreezeStatusResp
    -- Config operations
    :<|> "rpc" :> "config" :> "show" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [(String, Double)]
    :<|> "rpc" :> "config" :> "set" :> ReqBody '[JSON] RpcConfigSet :> Post '[JSON] RpcOk
    :<|> "rpc" :> "config" :> "presets" :> ReqBody '[JSON] RpcPresetName :> Post '[JSON] RpcOk
    :<|> "rpc" :> "config" :> "reset" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] RpcOk
    :<|> "rpc" :> "config" :> "set-pay-period" :> ReqBody '[JSON] SetPayPeriodReq :> Post '[JSON] RpcOk
    -- Audit
    :<|> "rpc" :> "audit" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [AuditEntry]
    -- Checkpoints
    :<|> "rpc" :> "checkpoint" :> "create" :> ReqBody '[JSON] CreateCheckpointReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "checkpoint" :> "commit" :> ReqBody '[JSON] RpcCheckpointName :> Post '[JSON] RpcOk
    :<|> "rpc" :> "checkpoint" :> "rollback" :> ReqBody '[JSON] RpcCheckpointName :> Post '[JSON] RpcOk
    -- Import / Export
    :<|> "rpc" :> "export" :> "all" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] ExportResp
    :<|> "rpc" :> "import" :> "data" :> ReqBody '[JSON] ImportReq :> Post '[JSON] ImportResp
    -- Absence types
    :<|> "rpc" :> "absence-type" :> "create" :> ReqBody '[JSON] CreateAbsenceTypeReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "absence-type" :> "delete" :> ReqBody '[JSON] RpcAbsenceTypeId :> Post '[JSON] RpcOk
    :<|> "rpc" :> "absence-type" :> "set-allowance" :> ReqBody '[JSON] RpcSetAllowance :> Post '[JSON] RpcOk
    -- Absences
    :<|> "rpc" :> "absence" :> "request" :> ReqBody '[JSON] RequestAbsenceReq :> Post '[JSON] AbsenceCreatedResp
    :<|> "rpc" :> "absence" :> "approve" :> ReqBody '[JSON] RpcAbsenceId :> Post '[JSON] RpcOk
    :<|> "rpc" :> "absence" :> "reject" :> ReqBody '[JSON] RpcAbsenceId :> Post '[JSON] RpcOk
    :<|> "rpc" :> "absence" :> "list-pending" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [AbsenceRequest]
    -- Users
    :<|> "rpc" :> "user" :> "create" :> ReqBody '[JSON] CreateUserReq :> Post '[JSON] RpcOk
    :<|> "rpc" :> "user" :> "list" :> ReqBody '[JSON] RpcEmpty :> Post '[JSON] [User]
    :<|> "rpc" :> "user" :> "delete" :> ReqBody '[JSON] RpcUsername :> Post '[JSON] RpcOk
    -- Hint sessions
    :<|> "rpc" :> "what-if" :> "add" :> ReqBody '[JSON] AddHintReq :> Post '[JSON] [Hint]
    :<|> "rpc" :> "what-if" :> "revert" :> ReqBody '[JSON] HintSessionRef :> Post '[JSON] [Hint]
    :<|> "rpc" :> "what-if" :> "list" :> ReqBody '[JSON] HintSessionRef :> Post '[JSON] [Hint]
    :<|> "rpc" :> "what-if" :> "apply" :> ReqBody '[JSON] HintSessionRef :> Post '[JSON] RpcOk
    :<|> "rpc" :> "what-if" :> "rebase" :> ReqBody '[JSON] HintSessionRef :> Post '[JSON] RebaseResultResp
    -- Session management
    :<|> "rpc" :> "session" :> "create" :> ReqBody '[JSON] RpcSessionCreate :> Post '[JSON] RpcSessionResp
    :<|> "rpc" :> "session" :> "resume" :> ReqBody '[JSON] RpcSessionCreate :> Post '[JSON] RpcSessionResp
    -- Command execution (returns plain text, not JSON)
    :<|> "rpc" :> "execute" :> ReqBody '[JSON] ExecuteReq :> Post '[PlainText] String

rpcApi :: Proxy RpcAPI
rpcApi = Proxy

-- -----------------------------------------------------------------
-- RPC-specific request/response types
-- -----------------------------------------------------------------

-- | Standard success response for void-returning operations.
data RpcOk = RpcOk deriving (Show, Eq)

instance ToJSON RpcOk where
    toJSON _ = object ["ok" .= True]

instance FromJSON RpcOk where
    parseJSON = withObject "RpcOk" $ \_ -> pure RpcOk

-- | Empty request body for parameterless commands.
data RpcEmpty = RpcEmpty deriving (Show)

instance ToJSON RpcEmpty where
    toJSON _ = object []

instance FromJSON RpcEmpty where
    parseJSON = withObject "RpcEmpty" $ \_ -> pure RpcEmpty

-- | Identifier wrappers for RPC endpoints.
newtype RpcSkillId = RpcSkillId { rsiId :: Int } deriving (Show)
instance ToJSON RpcSkillId where toJSON r = object ["id" .= rsiId r]
instance FromJSON RpcSkillId where parseJSON = withObject "RpcSkillId" $ \v -> RpcSkillId <$> v .: "id"

newtype RpcStationId = RpcStationId { rstId :: Int } deriving (Show)
instance ToJSON RpcStationId where toJSON r = object ["id" .= rstId r]
instance FromJSON RpcStationId where parseJSON = withObject "RpcStationId" $ \v -> RpcStationId <$> v .: "id"

data RpcStationHours = RpcStationHours { rshSid :: !Int, rshStart :: !Int, rshEnd :: !Int } deriving (Show)
instance ToJSON RpcStationHours where toJSON r = object ["stationId" .= rshSid r, "start" .= rshStart r, "end" .= rshEnd r]
instance FromJSON RpcStationHours where parseJSON = withObject "RpcStationHours" $ \v -> RpcStationHours <$> v .: "stationId" <*> v .: "start" <*> v .: "end"

data SetStationClosureReq' = SetStationClosureReq' { sscr'Sid :: !Int, sscr'Day :: !Day } deriving (Show)
instance ToJSON SetStationClosureReq' where toJSON r = object ["stationId" .= sscr'Sid r, "day" .= sscr'Day r]
instance FromJSON SetStationClosureReq' where parseJSON = withObject "SetStationClosureReq'" $ \v -> SetStationClosureReq' <$> v .: "stationId" <*> v .: "day"

newtype RpcShiftName = RpcShiftName { rsnName :: String } deriving (Show)
instance ToJSON RpcShiftName where toJSON r = object ["name" .= rsnName r]
instance FromJSON RpcShiftName where parseJSON = withObject "RpcShiftName" $ \v -> RpcShiftName <$> v .: "name"

data RpcWorkerHours = RpcWorkerHours { rwhWid :: !Int, rwhHours :: !Int } deriving (Show)
instance ToJSON RpcWorkerHours where toJSON r = object ["workerId" .= rwhWid r, "hours" .= rwhHours r]
instance FromJSON RpcWorkerHours where parseJSON = withObject "RpcWorkerHours" $ \v -> RpcWorkerHours <$> v .: "workerId" <*> v .: "hours"

data RpcWorkerOvertime = RpcWorkerOvertime { rwoWid :: !Int, rwoOptIn :: !Bool } deriving (Show)
instance ToJSON RpcWorkerOvertime where toJSON r = object ["workerId" .= rwoWid r, "optIn" .= rwoOptIn r]
instance FromJSON RpcWorkerOvertime where parseJSON = withObject "RpcWorkerOvertime" $ \v -> RpcWorkerOvertime <$> v .: "workerId" <*> v .: "optIn"

data RpcWorkerPrefs = RpcWorkerPrefs { rwpWid :: !Int, rwpStationIds :: ![Int] } deriving (Show)
instance ToJSON RpcWorkerPrefs where toJSON r = object ["workerId" .= rwpWid r, "stationIds" .= rwpStationIds r]
instance FromJSON RpcWorkerPrefs where parseJSON = withObject "RpcWorkerPrefs" $ \v -> RpcWorkerPrefs <$> v .: "workerId" <*> v .: "stationIds"

data RpcWorkerVariety = RpcWorkerVariety { rwvWid :: !Int, rwvPrefer :: !Bool } deriving (Show)
instance ToJSON RpcWorkerVariety where toJSON r = object ["workerId" .= rwvWid r, "prefer" .= rwvPrefer r]
instance FromJSON RpcWorkerVariety where parseJSON = withObject "RpcWorkerVariety" $ \v -> RpcWorkerVariety <$> v .: "workerId" <*> v .: "prefer"

data RpcWorkerShiftPrefs = RpcWorkerShiftPrefs { rwspWid :: !Int, rwspShifts :: ![String] } deriving (Show)
instance ToJSON RpcWorkerShiftPrefs where toJSON r = object ["workerId" .= rwspWid r, "shifts" .= rwspShifts r]
instance FromJSON RpcWorkerShiftPrefs where parseJSON = withObject "RpcWorkerShiftPrefs" $ \v -> RpcWorkerShiftPrefs <$> v .: "workerId" <*> v .: "shifts"

data RpcWorkerWeekendOnly = RpcWorkerWeekendOnly { rwwoWid :: !Int, rwwoVal :: !Bool } deriving (Show)
instance ToJSON RpcWorkerWeekendOnly where toJSON r = object ["workerId" .= rwwoWid r, "weekendOnly" .= rwwoVal r]
instance FromJSON RpcWorkerWeekendOnly where parseJSON = withObject "RpcWorkerWeekendOnly" $ \v -> RpcWorkerWeekendOnly <$> v .: "workerId" <*> v .: "weekendOnly"

data RpcWorkerSeniority = RpcWorkerSeniority { rwsWid :: !Int, rwsLevel :: !Int } deriving (Show)
instance ToJSON RpcWorkerSeniority where toJSON r = object ["workerId" .= rwsWid r, "level" .= rwsLevel r]
instance FromJSON RpcWorkerSeniority where parseJSON = withObject "RpcWorkerSeniority" $ \v -> RpcWorkerSeniority <$> v .: "workerId" <*> v .: "level"

data RpcWorkerCrossTraining = RpcWorkerCrossTraining { rwctWid :: !Int, rwctSkillId :: !Int } deriving (Show)
instance ToJSON RpcWorkerCrossTraining where toJSON r = object ["workerId" .= rwctWid r, "skillId" .= rwctSkillId r]
instance FromJSON RpcWorkerCrossTraining where parseJSON = withObject "RpcWorkerCrossTraining" $ \v -> RpcWorkerCrossTraining <$> v .: "workerId" <*> v .: "skillId"

data RpcWorkerEmploymentStatus = RpcWorkerEmploymentStatus { rwesWid :: !Int, rwesStatus :: !String } deriving (Show)
instance ToJSON RpcWorkerEmploymentStatus where toJSON r = object ["workerId" .= rwesWid r, "status" .= rwesStatus r]
instance FromJSON RpcWorkerEmploymentStatus where parseJSON = withObject "RpcWorkerEmploymentStatus" $ \v -> RpcWorkerEmploymentStatus <$> v .: "workerId" <*> v .: "status"

data RpcWorkerOvertimeModel = RpcWorkerOvertimeModel { rwomWid :: !Int, rwomModel :: !OvertimeModel } deriving (Show)
instance ToJSON RpcWorkerOvertimeModel where toJSON r = object ["workerId" .= rwomWid r, "model" .= rwomModel r]
instance FromJSON RpcWorkerOvertimeModel where parseJSON = withObject "RpcWorkerOvertimeModel" $ \v -> RpcWorkerOvertimeModel <$> v .: "workerId" <*> v .: "model"

data RpcWorkerPayTracking = RpcWorkerPayTracking { rwptWid :: !Int, rwptTracking :: !PayPeriodTracking } deriving (Show)
instance ToJSON RpcWorkerPayTracking where toJSON r = object ["workerId" .= rwptWid r, "tracking" .= rwptTracking r]
instance FromJSON RpcWorkerPayTracking where parseJSON = withObject "RpcWorkerPayTracking" $ \v -> RpcWorkerPayTracking <$> v .: "workerId" <*> v .: "tracking"

data RpcWorkerTemp = RpcWorkerTemp { rwtWid :: !Int, rwtTemp :: !Bool } deriving (Show)
instance ToJSON RpcWorkerTemp where toJSON r = object ["workerId" .= rwtWid r, "temp" .= rwtTemp r]
instance FromJSON RpcWorkerTemp where parseJSON = withObject "RpcWorkerTemp" $ \v -> RpcWorkerTemp <$> v .: "workerId" <*> v .: "temp"

data RpcWorkerSkill = RpcWorkerSkill { rwskWid :: !Int, rwskSkillId :: !Int } deriving (Show)
instance ToJSON RpcWorkerSkill where toJSON r = object ["workerId" .= rwskWid r, "skillId" .= rwskSkillId r]
instance FromJSON RpcWorkerSkill where parseJSON = withObject "RpcWorkerSkill" $ \v -> RpcWorkerSkill <$> v .: "workerId" <*> v .: "skillId"

data RpcWorkerPairing = RpcWorkerPairing { rwprWid :: !Int, rwprOtherId :: !Int } deriving (Show)
instance ToJSON RpcWorkerPairing where toJSON r = object ["workerId" .= rwprWid r, "otherWorkerId" .= rwprOtherId r]
instance FromJSON RpcWorkerPairing where parseJSON = withObject "RpcWorkerPairing" $ \v -> RpcWorkerPairing <$> v .: "workerId" <*> v .: "otherWorkerId"

newtype RpcDraftId = RpcDraftId { rdiId :: Int } deriving (Show)
instance ToJSON RpcDraftId where toJSON r = object ["draftId" .= rdiId r]
instance FromJSON RpcDraftId where parseJSON = withObject "RpcDraftId" $ \v -> RpcDraftId <$> v .: "draftId"

data RpcDraftGenerate = RpcDraftGenerate { rdgDraftId :: !Int, rdgWorkerIds :: ![Int] } deriving (Show)
instance ToJSON RpcDraftGenerate where toJSON r = object ["draftId" .= rdgDraftId r, "workerIds" .= rdgWorkerIds r]
instance FromJSON RpcDraftGenerate where parseJSON = withObject "RpcDraftGenerate" $ \v -> RpcDraftGenerate <$> v .: "draftId" <*> v .: "workerIds"

data RpcDraftCommit = RpcDraftCommit { rdcDraftId :: !Int, rdcNote :: !String } deriving (Show)
instance ToJSON RpcDraftCommit where toJSON r = object ["draftId" .= rdcDraftId r, "note" .= rdcNote r]
instance FromJSON RpcDraftCommit where parseJSON = withObject "RpcDraftCommit" $ \v -> RpcDraftCommit <$> v .: "draftId" <*> v .: "note"

newtype RpcScheduleName = RpcScheduleName { rsnmName :: String } deriving (Show)
instance ToJSON RpcScheduleName where toJSON r = object ["name" .= rsnmName r]
instance FromJSON RpcScheduleName where parseJSON = withObject "RpcScheduleName" $ \v -> RpcScheduleName <$> v .: "name"

data RpcDateRange = RpcDateRange { rdrFrom :: !Day, rdrTo :: !Day } deriving (Show)
instance ToJSON RpcDateRange where toJSON r = object ["from" .= rdrFrom r, "to" .= rdrTo r]
instance FromJSON RpcDateRange where parseJSON = withObject "RpcDateRange" $ \v -> RpcDateRange <$> v .: "from" <*> v .: "to"

data RpcConfigSet = RpcConfigSet { rcsKey :: !String, rcsValue :: !Double } deriving (Show)
instance ToJSON RpcConfigSet where toJSON r = object ["key" .= rcsKey r, "value" .= rcsValue r]
instance FromJSON RpcConfigSet where parseJSON = withObject "RpcConfigSet" $ \v -> RpcConfigSet <$> v .: "key" <*> v .: "value"

newtype RpcPresetName = RpcPresetName { rpnName :: String } deriving (Show)
instance ToJSON RpcPresetName where toJSON r = object ["name" .= rpnName r]
instance FromJSON RpcPresetName where parseJSON = withObject "RpcPresetName" $ \v -> RpcPresetName <$> v .: "name"

newtype RpcCheckpointName = RpcCheckpointName { rcnName :: String } deriving (Show)
instance ToJSON RpcCheckpointName where toJSON r = object ["name" .= rcnName r]
instance FromJSON RpcCheckpointName where parseJSON = withObject "RpcCheckpointName" $ \v -> RpcCheckpointName <$> v .: "name"

newtype RpcAbsenceTypeId = RpcAbsenceTypeId { ratiId :: Int } deriving (Show)
instance ToJSON RpcAbsenceTypeId where toJSON r = object ["id" .= ratiId r]
instance FromJSON RpcAbsenceTypeId where parseJSON = withObject "RpcAbsenceTypeId" $ \v -> RpcAbsenceTypeId <$> v .: "id"

data RpcSetAllowance = RpcSetAllowance { rsaTypeId :: !Int, rsaWorkerId :: !Int, rsaAllowance :: !Int } deriving (Show)
instance ToJSON RpcSetAllowance where toJSON r = object ["typeId" .= rsaTypeId r, "workerId" .= rsaWorkerId r, "allowance" .= rsaAllowance r]
instance FromJSON RpcSetAllowance where parseJSON = withObject "RpcSetAllowance" $ \v -> RpcSetAllowance <$> v .: "typeId" <*> v .: "workerId" <*> v .: "allowance"

newtype RpcAbsenceId = RpcAbsenceId { raiId :: Int } deriving (Show)
instance ToJSON RpcAbsenceId where toJSON r = object ["id" .= raiId r]
instance FromJSON RpcAbsenceId where parseJSON = withObject "RpcAbsenceId" $ \v -> RpcAbsenceId <$> v .: "id"

newtype RpcUsername = RpcUsername { ruName :: String } deriving (Show)
instance ToJSON RpcUsername where toJSON r = object ["username" .= ruName r]
instance FromJSON RpcUsername where parseJSON = withObject "RpcUsername" $ \v -> RpcUsername <$> v .: "username"

newtype RpcSessionCreate = RpcSessionCreate { rscUserId :: Int } deriving (Show)
instance ToJSON RpcSessionCreate where toJSON r = object ["userId" .= rscUserId r]
instance FromJSON RpcSessionCreate where parseJSON = withObject "RpcSessionCreate" $ \v -> RpcSessionCreate <$> v .: "userId"

newtype RpcSessionResp = RpcSessionResp { rsrSessionId :: Int } deriving (Show)
instance ToJSON RpcSessionResp where toJSON r = object ["sessionId" .= rsrSessionId r]
instance FromJSON RpcSessionResp where parseJSON = withObject "RpcSessionResp" $ \v -> RpcSessionResp <$> v .: "sessionId"

-- | Request body for /rpc/execute — a raw command string with optional client ID.
data ExecuteReq = ExecuteReq
    { erCommand  :: String
    , erClientId :: Maybe String
    } deriving (Show)
instance ToJSON ExecuteReq where
    toJSON r = object ["command" .= erCommand r, "clientId" .= erClientId r]
instance FromJSON ExecuteReq where
    parseJSON = withObject "ExecuteReq" $ \v ->
        ExecuteReq <$> v .: "command" <*> v .:? "clientId"

-- -----------------------------------------------------------------
-- RPC Server (handlers)
-- -----------------------------------------------------------------

rpcServer :: ExecuteEnv -> Repository -> User -> Server RpcAPI
rpcServer execEnv repo _user =
    let cmdBus = busCommands (eeBus execEnv)
    in
    -- Skill CRUD
         rpcCreateSkill cmdBus repo
    :<|> rpcDeleteSkill cmdBus repo
    :<|> rpcRenameSkill cmdBus repo
    :<|> rpcListSkills repo
    -- Station CRUD
    :<|> rpcCreateStation cmdBus repo
    :<|> rpcDeleteStation cmdBus repo
    :<|> rpcSetStationHours cmdBus repo
    :<|> rpcCloseStationDay cmdBus repo
    :<|> rpcListStations repo
    -- Shift CRUD
    :<|> rpcCreateShift cmdBus repo
    :<|> rpcDeleteShift cmdBus repo
    :<|> rpcListShifts repo
    -- Worker configuration
    :<|> rpcSetWorkerHours cmdBus repo
    :<|> rpcSetWorkerOvertime cmdBus repo
    :<|> rpcSetWorkerPrefs cmdBus repo
    :<|> rpcSetWorkerVariety cmdBus repo
    :<|> rpcSetWorkerShiftPrefs cmdBus repo
    :<|> rpcSetWorkerWeekendOnly cmdBus repo
    :<|> rpcSetWorkerSeniority cmdBus repo
    :<|> rpcAddCrossTraining cmdBus repo
    :<|> rpcSetEmploymentStatus cmdBus repo
    :<|> rpcSetOvertimeModel cmdBus repo
    :<|> rpcSetPayTracking cmdBus repo
    :<|> rpcSetTemp cmdBus repo
    :<|> rpcGrantSkill cmdBus repo
    :<|> rpcRevokeSkill cmdBus repo
    :<|> rpcAvoidPairing cmdBus repo
    :<|> rpcPreferPairing cmdBus repo
    -- Pins
    :<|> rpcAddPin cmdBus repo
    :<|> rpcRemovePin cmdBus repo
    :<|> rpcListPins repo
    -- Drafts
    :<|> rpcCreateDraft repo
    :<|> rpcListDrafts repo
    :<|> rpcViewDraft repo
    :<|> rpcGenerateDraft repo
    :<|> rpcCommitDraft cmdBus repo
    :<|> rpcDiscardDraft cmdBus repo
    -- Schedules
    :<|> rpcListSchedules repo
    :<|> rpcViewSchedule repo
    :<|> rpcDeleteSchedule cmdBus repo
    -- Calendar
    :<|> rpcViewCalendar repo
    :<|> rpcCalendarHistory repo
    :<|> rpcUnfreeze
    :<|> rpcFreezeStatus
    -- Config
    :<|> rpcShowConfig repo
    :<|> rpcSetConfig cmdBus repo
    :<|> rpcApplyPreset cmdBus repo
    :<|> rpcResetConfig cmdBus repo
    :<|> rpcSetPayPeriod cmdBus repo
    -- Audit
    :<|> rpcListAudit repo
    -- Checkpoints
    :<|> rpcCreateCheckpoint cmdBus repo
    :<|> rpcCommitCheckpoint cmdBus repo
    :<|> rpcRollbackCheckpoint cmdBus repo
    -- Import/Export
    :<|> rpcExportAll repo
    :<|> rpcImportData repo
    -- Absence types
    :<|> rpcCreateAbsenceType cmdBus repo
    :<|> rpcDeleteAbsenceType cmdBus repo
    :<|> rpcSetAllowance cmdBus repo
    -- Absences
    :<|> rpcRequestAbsence repo
    :<|> rpcApproveAbsence repo
    :<|> rpcRejectAbsence repo
    :<|> rpcListPendingAbsences repo
    -- Users
    :<|> rpcCreateUser cmdBus repo
    :<|> rpcListUsers repo
    :<|> rpcDeleteUser cmdBus repo
    -- Hints
    :<|> rpcAddHint repo
    :<|> rpcRevertHint repo
    :<|> rpcListHints repo
    :<|> rpcApplyHints repo
    :<|> rpcRebaseHints repo
    -- Sessions
    :<|> rpcCreateSession repo
    :<|> rpcResumeSession repo
    -- Command execution
    :<|> rpcExecute cmdBus execEnv repo _user

-- -----------------------------------------------------------------
-- Audit logging helper
-- -----------------------------------------------------------------

-- | Publish an RPC command event to the bus.
logRpcBus :: TopicBus CommandEvent -> String -> Handler ()
logRpcBus cmdBus cmd = liftIO $ publishCommand cmdBus RPC "rpc" cmd

-- -----------------------------------------------------------------
-- Skill handlers
-- -----------------------------------------------------------------

rpcCreateSkill :: TopicBus CommandEvent -> Repository -> CreateSkillReq -> Handler RpcOk
rpcCreateSkill cmdBus repo req = do
    result <- liftIO $ SW.addSkill repo (csrName req) (csrDescription req)
    case result of
        Left err -> throwApiError (Conflict err)
        Right () -> do
            let cmd = "skill create " ++ shellQuote (csrName req)
            liftIO $ publishCommand cmdBus RPC "rpc" cmd
            pure RpcOk

rpcDeleteSkill :: TopicBus CommandEvent -> Repository -> RpcSkillId -> Handler RpcOk
rpcDeleteSkill cmdBus repo req = do
    liftIO $ SW.removeSkill repo (SkillId (rsiId req))
    let cmd = "skill delete " ++ show (rsiId req)
    liftIO $ publishCommand cmdBus RPC "rpc" cmd
    pure RpcOk

rpcRenameSkill :: TopicBus CommandEvent -> Repository -> Int -> RenameSkillReq -> Handler RpcOk
rpcRenameSkill cmdBus repo sid req = do
    liftIO $ repoRenameSkill repo (SkillId sid) (rsrName req)
    let cmd = "skill rename " ++ show sid ++ " " ++ shellQuote (rsrName req)
    liftIO $ publishCommand cmdBus RPC "rpc" cmd
    pure RpcOk

rpcListSkills :: Repository -> RpcEmpty -> Handler [(SkillId, Skill)]
rpcListSkills repo _ = liftIO $ SW.listSkills repo

-- -----------------------------------------------------------------
-- Station handlers
-- -----------------------------------------------------------------

rpcCreateStation :: TopicBus CommandEvent -> Repository -> CreateStationReq -> Handler RpcOk
rpcCreateStation cmdBus repo req = do
    liftIO $ SW.addStation repo (StationId (cstrId req)) (cstrName req)
    logRpcBus cmdBus ("station add " ++ show (cstrId req) ++ " " ++ shellQuote (cstrName req))
    pure RpcOk

rpcDeleteStation :: TopicBus CommandEvent -> Repository -> RpcStationId -> Handler RpcOk
rpcDeleteStation cmdBus repo req = do
    liftIO $ SW.removeStation repo (StationId (rstId req))
    logRpcBus cmdBus ("station remove " ++ show (rstId req))
    pure RpcOk

rpcSetStationHours :: TopicBus CommandEvent -> Repository -> RpcStationHours -> Handler RpcOk
rpcSetStationHours cmdBus repo req = do
    liftIO $ SW.setStationHours repo (StationId (rshSid req)) (rshStart req) (rshEnd req)
    logRpcBus cmdBus ("station set-hours " ++ show (rshSid req) ++ " " ++ show (rshStart req) ++ " " ++ show (rshEnd req))
    pure RpcOk

rpcCloseStationDay :: TopicBus CommandEvent -> Repository -> SetStationClosureReq' -> Handler RpcOk
rpcCloseStationDay cmdBus repo req = do
    let dow = dayOfWeek (sscr'Day req)
    liftIO $ SW.closeStationDay repo (StationId (sscr'Sid req)) dow
    logRpcBus cmdBus ("station close-day " ++ show (sscr'Sid req) ++ " " ++ show (sscr'Day req))
    pure RpcOk

rpcListStations :: Repository -> RpcEmpty -> Handler [(Int, String)]
rpcListStations repo _ = do
    stations <- liftIO $ SW.listStations repo
    pure [(i, n) | (StationId i, n) <- stations]

-- -----------------------------------------------------------------
-- Shift handlers
-- -----------------------------------------------------------------

rpcCreateShift :: TopicBus CommandEvent -> Repository -> CreateShiftReq -> Handler RpcOk
rpcCreateShift cmdBus repo req = do
    liftIO $ repoSaveShift repo (ShiftDef (cshrName req) (cshrStart req) (cshrEnd req))
    logRpcBus cmdBus ("shift create " ++ shellQuote (cshrName req))
    pure RpcOk

rpcDeleteShift :: TopicBus CommandEvent -> Repository -> RpcShiftName -> Handler RpcOk
rpcDeleteShift cmdBus repo req = do
    liftIO $ repoDeleteShift repo (rsnName req)
    logRpcBus cmdBus ("shift delete " ++ shellQuote (rsnName req))
    pure RpcOk

rpcListShifts :: Repository -> RpcEmpty -> Handler [ShiftDef]
rpcListShifts repo _ = liftIO $ repoLoadShifts repo

-- -----------------------------------------------------------------
-- Worker configuration handlers
-- -----------------------------------------------------------------

rpcSetWorkerHours :: TopicBus CommandEvent -> Repository -> RpcWorkerHours -> Handler RpcOk
rpcSetWorkerHours cmdBus repo req = do
    liftIO $ SW.setMaxHours repo (WorkerId (rwhWid req)) (fromIntegral (rwhHours req))
    logRpcBus cmdBus ("worker set-hours " ++ show (rwhWid req) ++ " " ++ show (rwhHours req))
    pure RpcOk

rpcSetWorkerOvertime :: TopicBus CommandEvent -> Repository -> RpcWorkerOvertime -> Handler RpcOk
rpcSetWorkerOvertime cmdBus repo req = do
    _ <- liftIO $ SW.setOvertimeOptIn repo (WorkerId (rwoWid req)) (rwoOptIn req)
    logRpcBus cmdBus ("worker set-overtime " ++ show (rwoWid req) ++ " " ++ show (rwoOptIn req))
    pure RpcOk

rpcSetWorkerPrefs :: TopicBus CommandEvent -> Repository -> RpcWorkerPrefs -> Handler RpcOk
rpcSetWorkerPrefs cmdBus repo req = do
    liftIO $ SW.setStationPreferences repo (WorkerId (rwpWid req)) (map StationId (rwpStationIds req))
    logRpcBus cmdBus ("worker set-prefs " ++ show (rwpWid req))
    pure RpcOk

rpcSetWorkerVariety :: TopicBus CommandEvent -> Repository -> RpcWorkerVariety -> Handler RpcOk
rpcSetWorkerVariety cmdBus repo req = do
    liftIO $ SW.setVarietyPreference repo (WorkerId (rwvWid req)) (rwvPrefer req)
    logRpcBus cmdBus ("worker set-variety " ++ show (rwvWid req) ++ " " ++ show (rwvPrefer req))
    pure RpcOk

rpcSetWorkerShiftPrefs :: TopicBus CommandEvent -> Repository -> RpcWorkerShiftPrefs -> Handler RpcOk
rpcSetWorkerShiftPrefs cmdBus repo req = do
    liftIO $ SW.setShiftPreferences repo (WorkerId (rwspWid req)) (rwspShifts req)
    logRpcBus cmdBus ("worker set-shift-prefs " ++ show (rwspWid req))
    pure RpcOk

rpcSetWorkerWeekendOnly :: TopicBus CommandEvent -> Repository -> RpcWorkerWeekendOnly -> Handler RpcOk
rpcSetWorkerWeekendOnly cmdBus repo req = do
    liftIO $ SW.setWeekendOnly repo (WorkerId (rwwoWid req)) (rwwoVal req)
    logRpcBus cmdBus ("worker set-weekend-only " ++ show (rwwoWid req) ++ " " ++ show (rwwoVal req))
    pure RpcOk

rpcSetWorkerSeniority :: TopicBus CommandEvent -> Repository -> RpcWorkerSeniority -> Handler RpcOk
rpcSetWorkerSeniority cmdBus repo req = do
    liftIO $ SW.setSeniority repo (WorkerId (rwsWid req)) (rwsLevel req)
    logRpcBus cmdBus ("worker set-seniority " ++ show (rwsWid req) ++ " " ++ show (rwsLevel req))
    pure RpcOk

rpcAddCrossTraining :: TopicBus CommandEvent -> Repository -> RpcWorkerCrossTraining -> Handler RpcOk
rpcAddCrossTraining cmdBus repo req = do
    liftIO $ SW.addCrossTraining repo (WorkerId (rwctWid req)) (SkillId (rwctSkillId req))
    logRpcBus cmdBus ("worker set-cross-training " ++ show (rwctWid req) ++ " " ++ show (rwctSkillId req))
    pure RpcOk

rpcSetEmploymentStatus :: TopicBus CommandEvent -> Repository -> RpcWorkerEmploymentStatus -> Handler RpcOk
rpcSetEmploymentStatus cmdBus repo req = do
    _ <- liftIO $ SW.setEmploymentStatus repo (WorkerId (rwesWid req)) (rwesStatus req)
    logRpcBus cmdBus ("worker set-status " ++ show (rwesWid req) ++ " " ++ shellQuote (rwesStatus req))
    pure RpcOk

rpcSetOvertimeModel :: TopicBus CommandEvent -> Repository -> RpcWorkerOvertimeModel -> Handler RpcOk
rpcSetOvertimeModel cmdBus repo req = do
    liftIO $ SW.setOvertimeModel repo (WorkerId (rwomWid req)) (rwomModel req)
    logRpcBus cmdBus ("worker set-overtime-model " ++ show (rwomWid req))
    pure RpcOk

rpcSetPayTracking :: TopicBus CommandEvent -> Repository -> RpcWorkerPayTracking -> Handler RpcOk
rpcSetPayTracking cmdBus repo req = do
    liftIO $ SW.setPayPeriodTracking repo (WorkerId (rwptWid req)) (rwptTracking req)
    logRpcBus cmdBus ("worker set-pay-tracking " ++ show (rwptWid req))
    pure RpcOk

rpcSetTemp :: TopicBus CommandEvent -> Repository -> RpcWorkerTemp -> Handler RpcOk
rpcSetTemp cmdBus repo req = do
    liftIO $ SW.setTempFlag repo (WorkerId (rwtWid req)) (rwtTemp req)
    logRpcBus cmdBus ("worker set-temp " ++ show (rwtWid req) ++ " " ++ show (rwtTemp req))
    pure RpcOk

rpcGrantSkill :: TopicBus CommandEvent -> Repository -> RpcWorkerSkill -> Handler RpcOk
rpcGrantSkill cmdBus repo req = do
    liftIO $ SW.grantWorkerSkill repo (WorkerId (rwskWid req)) (SkillId (rwskSkillId req))
    logRpcBus cmdBus ("worker grant-skill " ++ show (rwskWid req) ++ " " ++ show (rwskSkillId req))
    pure RpcOk

rpcRevokeSkill :: TopicBus CommandEvent -> Repository -> RpcWorkerSkill -> Handler RpcOk
rpcRevokeSkill cmdBus repo req = do
    liftIO $ SW.revokeWorkerSkill repo (WorkerId (rwskWid req)) (SkillId (rwskSkillId req))
    logRpcBus cmdBus ("worker revoke-skill " ++ show (rwskWid req) ++ " " ++ show (rwskSkillId req))
    pure RpcOk

rpcAvoidPairing :: TopicBus CommandEvent -> Repository -> RpcWorkerPairing -> Handler RpcOk
rpcAvoidPairing cmdBus repo req = do
    liftIO $ SW.addAvoidPairing repo (WorkerId (rwprWid req)) (WorkerId (rwprOtherId req))
    logRpcBus cmdBus ("worker avoid-pairing " ++ show (rwprWid req) ++ " " ++ show (rwprOtherId req))
    pure RpcOk

rpcPreferPairing :: TopicBus CommandEvent -> Repository -> RpcWorkerPairing -> Handler RpcOk
rpcPreferPairing cmdBus repo req = do
    liftIO $ SW.addPreferPairing repo (WorkerId (rwprWid req)) (WorkerId (rwprOtherId req))
    logRpcBus cmdBus ("worker prefer-pairing " ++ show (rwprWid req) ++ " " ++ show (rwprOtherId req))
    pure RpcOk

-- -----------------------------------------------------------------
-- Pin handlers
-- -----------------------------------------------------------------

rpcAddPin :: TopicBus CommandEvent -> Repository -> PinnedAssignment -> Handler RpcOk
rpcAddPin cmdBus repo pin = do
    liftIO (SW.addPin repo pin)
    logRpcBus cmdBus ("pin add " ++ show (pinWorker pin) ++ " " ++ show (pinStation pin))
    pure RpcOk

rpcRemovePin :: TopicBus CommandEvent -> Repository -> PinnedAssignment -> Handler RpcOk
rpcRemovePin cmdBus repo pin = do
    liftIO (SW.removePin repo pin)
    logRpcBus cmdBus ("pin remove " ++ show (pinWorker pin) ++ " " ++ show (pinStation pin))
    pure RpcOk

rpcListPins :: Repository -> RpcEmpty -> Handler [PinnedAssignment]
rpcListPins repo _ = liftIO $ SW.listPins repo

-- -----------------------------------------------------------------
-- Draft handlers
-- -----------------------------------------------------------------

rpcCreateDraft :: Repository -> CreateDraftReq -> Handler DraftCreatedResp
rpcCreateDraft repo req = do
    result <- liftIO $ SD.createDraft repo (cdrDateFrom req) (cdrDateTo req)
    case result of
        Left msg  -> throwApiError (Conflict msg)
        Right did -> pure (DraftCreatedResp did)

rpcListDrafts :: Repository -> RpcEmpty -> Handler [DraftInfo]
rpcListDrafts repo _ = liftIO $ SD.listDrafts repo

rpcViewDraft :: Repository -> RpcDraftId -> Handler DraftInfo
rpcViewDraft repo req = do
    mDraft <- liftIO $ SD.loadDraft repo (rdiId req)
    case mDraft of
        Nothing -> throwApiError (NotFound "Draft not found")
        Just d  -> pure d

rpcGenerateDraft :: Repository -> RpcDraftGenerate -> Handler ScheduleResult
rpcGenerateDraft repo req = do
    let workers = Set.fromList (map WorkerId (rdgWorkerIds req))
    result <- liftIO $ SD.generateDraft repo (rdgDraftId req) workers
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right r  -> pure r

rpcCommitDraft :: TopicBus CommandEvent -> Repository -> RpcDraftCommit -> Handler RpcOk
rpcCommitDraft cmdBus repo req = do
    result <- liftIO $ SD.commitDraft repo (rdcDraftId req) (rdcNote req)
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> do
            logRpcBus cmdBus ("draft commit " ++ show (rdcDraftId req))
            pure RpcOk

rpcDiscardDraft :: TopicBus CommandEvent -> Repository -> RpcDraftId -> Handler RpcOk
rpcDiscardDraft cmdBus repo req = do
    result <- liftIO $ SD.discardDraft repo (rdiId req)
    case result of
        Left msg -> throwApiError (NotFound msg)
        Right () -> do
            logRpcBus cmdBus ("draft discard " ++ show (rdiId req))
            pure RpcOk

-- -----------------------------------------------------------------
-- Schedule handlers
-- -----------------------------------------------------------------

rpcListSchedules :: Repository -> RpcEmpty -> Handler [String]
rpcListSchedules repo _ = liftIO $ SS.listSchedules repo

rpcViewSchedule :: Repository -> RpcScheduleName -> Handler Schedule
rpcViewSchedule repo req = do
    mSched <- liftIO $ SS.getSchedule repo (rsnmName req)
    case mSched of
        Nothing -> throwApiError (NotFound ("Schedule not found: " ++ rsnmName req))
        Just s  -> pure s

rpcDeleteSchedule :: TopicBus CommandEvent -> Repository -> RpcScheduleName -> Handler RpcOk
rpcDeleteSchedule cmdBus repo req = do
    liftIO $ SS.deleteSchedule repo (rsnmName req)
    logRpcBus cmdBus ("schedule delete " ++ shellQuote (rsnmName req))
    pure RpcOk

-- -----------------------------------------------------------------
-- Calendar handlers
-- -----------------------------------------------------------------

rpcViewCalendar :: Repository -> RpcDateRange -> Handler Schedule
rpcViewCalendar repo req = liftIO $ SC.loadCalendarSlice repo (rdrFrom req) (rdrTo req)

rpcCalendarHistory :: Repository -> RpcEmpty -> Handler [CalendarCommit]
rpcCalendarHistory repo _ = liftIO $ SC.listCalendarHistory repo

rpcUnfreeze :: UnfreezeReq -> Handler RpcOk
rpcUnfreeze _ = pure RpcOk  -- session-level op, acknowledged

rpcFreezeStatus :: RpcEmpty -> Handler FreezeStatusResp
rpcFreezeStatus _ = do
    line <- liftIO SF.computeFreezeLine
    pure (FreezeStatusResp line)

-- -----------------------------------------------------------------
-- Config handlers
-- -----------------------------------------------------------------

rpcShowConfig :: Repository -> RpcEmpty -> Handler [(String, Double)]
rpcShowConfig repo _ = liftIO $ SCfg.listConfigParams repo

rpcSetConfig :: TopicBus CommandEvent -> Repository -> RpcConfigSet -> Handler RpcOk
rpcSetConfig cmdBus repo req = do
    result <- liftIO $ SCfg.setConfigParam repo (rcsKey req) (rcsValue req)
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown config key: " ++ rcsKey req))
        Just _  -> do
            logRpcBus cmdBus ("config set " ++ shellQuote (rcsKey req) ++ " " ++ show (rcsValue req))
            pure RpcOk

rpcApplyPreset :: TopicBus CommandEvent -> Repository -> RpcPresetName -> Handler RpcOk
rpcApplyPreset cmdBus repo req = do
    result <- liftIO $ SCfg.applyPreset repo (rpnName req)
    case result of
        Nothing -> throwApiError (BadRequest ("Unknown preset: " ++ rpnName req))
        Just _  -> do
            logRpcBus cmdBus ("config preset " ++ shellQuote (rpnName req))
            pure RpcOk

rpcResetConfig :: TopicBus CommandEvent -> Repository -> RpcEmpty -> Handler RpcOk
rpcResetConfig cmdBus repo _ = do
    liftIO $ SCfg.saveConfig repo =<< SCfg.loadConfig repo
    logRpcBus cmdBus "config reset"
    pure RpcOk

rpcSetPayPeriod :: TopicBus CommandEvent -> Repository -> SetPayPeriodReq -> Handler RpcOk
rpcSetPayPeriod cmdBus repo req = do
    case parsePayPeriodType (sprType req) of
        Nothing -> throwApiError (BadRequest ("Unknown pay period type: " ++ sprType req))
        Just pt -> do
            liftIO $ SCfg.savePayPeriodConfig repo (PayPeriodConfig pt (sprAnchorDate req))
            logRpcBus cmdBus ("config set-pay-period " ++ shellQuote (sprType req))
            pure RpcOk

-- -----------------------------------------------------------------
-- Audit handlers
-- -----------------------------------------------------------------

rpcListAudit :: Repository -> RpcEmpty -> Handler [AuditEntry]
rpcListAudit repo _ = liftIO $ repoGetAuditLog repo

-- -----------------------------------------------------------------
-- Checkpoint handlers
-- -----------------------------------------------------------------

rpcCreateCheckpoint :: TopicBus CommandEvent -> Repository -> CreateCheckpointReq -> Handler RpcOk
rpcCreateCheckpoint cmdBus repo req = do
    liftIO (repoSavepoint repo (ccrName req))
    logRpcBus cmdBus ("checkpoint create " ++ shellQuote (ccrName req))
    pure RpcOk

rpcCommitCheckpoint :: TopicBus CommandEvent -> Repository -> RpcCheckpointName -> Handler RpcOk
rpcCommitCheckpoint cmdBus repo req = do
    liftIO (repoRelease repo (rcnName req))
    logRpcBus cmdBus ("checkpoint commit " ++ shellQuote (rcnName req))
    pure RpcOk

rpcRollbackCheckpoint :: TopicBus CommandEvent -> Repository -> RpcCheckpointName -> Handler RpcOk
rpcRollbackCheckpoint cmdBus repo req = do
    liftIO (repoRollbackTo repo (rcnName req))
    logRpcBus cmdBus ("checkpoint rollback " ++ shellQuote (rcnName req))
    pure RpcOk

-- -----------------------------------------------------------------
-- Import / Export handlers
-- -----------------------------------------------------------------

rpcExportAll :: Repository -> RpcEmpty -> Handler ExportResp
rpcExportAll repo _ = ExportResp <$> liftIO (Exp.gatherExport repo Nothing)

rpcImportData :: Repository -> ImportReq -> Handler ImportResp
rpcImportData repo req = ImportResp <$> liftIO (Exp.applyImport repo (irData req))

-- -----------------------------------------------------------------
-- Absence type handlers
-- -----------------------------------------------------------------

rpcCreateAbsenceType :: TopicBus CommandEvent -> Repository -> CreateAbsenceTypeReq -> Handler RpcOk
rpcCreateAbsenceType cmdBus repo req = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let atId = AbsenceTypeId (catrId req)
        newType = AbsenceType (catrName req) (catrCountsAgainstAllowance req)
        ctx' = ctx { acTypes = Map.insert atId newType (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    logRpcBus cmdBus ("absence-type create " ++ show (catrId req) ++ " " ++ shellQuote (catrName req))
    pure RpcOk

rpcDeleteAbsenceType :: TopicBus CommandEvent -> Repository -> RpcAbsenceTypeId -> Handler RpcOk
rpcDeleteAbsenceType cmdBus repo req = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let ctx' = ctx { acTypes = Map.delete (AbsenceTypeId (ratiId req)) (acTypes ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    logRpcBus cmdBus ("absence-type delete " ++ show (ratiId req))
    pure RpcOk

rpcSetAllowance :: TopicBus CommandEvent -> Repository -> RpcSetAllowance -> Handler RpcOk
rpcSetAllowance cmdBus repo req = do
    ctx <- liftIO $ SA.loadAbsenceCtx repo
    let key = (WorkerId (rsaWorkerId req), AbsenceTypeId (rsaTypeId req))
        ctx' = ctx { acYearlyAllowance = Map.insert key (rsaAllowance req) (acYearlyAllowance ctx) }
    liftIO $ repoSaveAbsenceCtx repo ctx'
    logRpcBus cmdBus ("absence-type set-allowance " ++ show (rsaTypeId req) ++ " " ++ show (rsaWorkerId req))
    pure RpcOk

-- -----------------------------------------------------------------
-- Absence handlers
-- -----------------------------------------------------------------

rpcRequestAbsence :: Repository -> RequestAbsenceReq -> Handler AbsenceCreatedResp
rpcRequestAbsence repo req = do
    result <- liftIO $ SA.requestAbsenceService repo
        (WorkerId (rarWorkerId req)) (AbsenceTypeId (rarTypeId req))
        (rarFrom req) (rarTo req)
    case result of
        Left SA.UnknownAbsenceType -> throwApiError (BadRequest "Unknown absence type")
        Left err -> throwApiError (InternalError (show err))
        Right (AbsenceId aid) -> pure (AbsenceCreatedResp aid)

rpcApproveAbsence :: Repository -> RpcAbsenceId -> Handler RpcOk
rpcApproveAbsence repo req = do
    result <- liftIO $ SA.approveAbsenceService repo (AbsenceId (raiId req))
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left SA.AbsenceAllowanceExceeded -> throwApiError (Conflict "Allowance exceeded")
        Left err -> throwApiError (InternalError (show err))
        Right () -> pure RpcOk

rpcRejectAbsence :: Repository -> RpcAbsenceId -> Handler RpcOk
rpcRejectAbsence repo req = do
    result <- liftIO $ SA.rejectAbsenceService repo (AbsenceId (raiId req))
    case result of
        Left SA.AbsenceNotFound -> throwApiError (NotFound "Absence not found")
        Left err -> throwApiError (InternalError (show err))
        Right () -> pure RpcOk

rpcListPendingAbsences :: Repository -> RpcEmpty -> Handler [AbsenceRequest]
rpcListPendingAbsences repo _ = liftIO $ SA.listPendingAbsences repo

-- -----------------------------------------------------------------
-- User handlers
-- -----------------------------------------------------------------

rpcCreateUser :: TopicBus CommandEvent -> Repository -> CreateUserReq -> Handler RpcOk
rpcCreateUser cmdBus repo req = do
    result <- liftIO $ SAuth.register repo
        (curUsername req) (curPassword req) (curRole req) (WorkerId (curWorkerId req))
    case result of
        Left SAuth.UsernameTaken -> throwApiError (Conflict "Username already taken")
        Left err -> throwApiError (InternalError (show err))
        Right _ -> do
            logRpcBus cmdBus ("user create " ++ shellQuote (curUsername req))
            pure RpcOk

rpcListUsers :: Repository -> RpcEmpty -> Handler [User]
rpcListUsers repo _ = liftIO $ repoListUsers repo

rpcDeleteUser :: TopicBus CommandEvent -> Repository -> RpcUsername -> Handler RpcOk
rpcDeleteUser cmdBus repo req = do
    mUser <- liftIO $ repoGetUserByName repo (ruName req)
    case mUser of
        Nothing -> throwApiError (NotFound ("User not found: " ++ ruName req))
        Just u  -> do
            liftIO $ repoDeleteUser repo (userId u)
            logRpcBus cmdBus ("user delete " ++ shellQuote (ruName req))
            pure RpcOk

-- -----------------------------------------------------------------
-- Hint session handlers
-- -----------------------------------------------------------------

rpcAddHint :: Repository -> AddHintReq -> Handler [Hint]
rpcAddHint repo req = do
    let sid = SessionId (ahrSessionId req)
        did = ahrDraftId req
    mRec <- liftIO $ repoLoadHintSession repo sid did
    let currentHints = maybe [] hsHints mRec
        checkpoint   = maybe 0 hsCheckpoint mRec
        newHints     = currentHints ++ [ahrHint req]
    liftIO $ repoSaveHintSession repo sid did newHints checkpoint
    pure newHints

rpcRevertHint :: Repository -> HintSessionRef -> Handler [Hint]
rpcRevertHint repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    mRec <- liftIO $ repoLoadHintSession repo sid did
    case mRec of
        Nothing -> throwApiError (NotFound "No hint session found")
        Just rec -> do
            let hints = hsHints rec
            if null hints
                then throwApiError (BadRequest "No hints to revert")
                else do
                    let reverted = init hints
                    liftIO $ repoSaveHintSession repo sid did reverted (hsCheckpoint rec)
                    pure reverted

rpcListHints :: Repository -> HintSessionRef -> Handler [Hint]
rpcListHints repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    mRec <- liftIO $ repoLoadHintSession repo sid did
    pure $ maybe [] hsHints mRec

rpcApplyHints :: Repository -> HintSessionRef -> Handler RpcOk
rpcApplyHints repo ref = do
    let sid = SessionId (hsrSessionId ref)
        did = hsrDraftId ref
    liftIO $ repoDeleteHintSession repo sid did
    pure RpcOk

rpcRebaseHints :: Repository -> HintSessionRef -> Handler RebaseResultResp
rpcRebaseHints repo ref = do
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
                    let newCp = if null entries then hsCheckpoint rec else aeId (last entries)
                    liftIO $ repoSaveHintSession repo sid did (hsHints rec) newCp
                    pure (RebaseResultResp "auto-rebase"
                        ("Auto-rebased over " ++ show n ++ " compatible changes"))
                SHR.HasConflicts _ ->
                    pure (RebaseResultResp "has-conflicts"
                        "Some changes conflict with current hints")
                SHR.SessionInvalid msg ->
                    pure (RebaseResultResp "session-invalid" msg)

-- -----------------------------------------------------------------
-- Session management handlers
-- -----------------------------------------------------------------

rpcCreateSession :: Repository -> RpcSessionCreate -> Handler RpcSessionResp
rpcCreateSession repo req = do
    let uid = UserId (rscUserId req)
    (SessionId sid, _tok) <- liftIO $ repoCreateSession repo uid
    pure (RpcSessionResp sid)

rpcResumeSession :: Repository -> RpcSessionCreate -> Handler RpcSessionResp
rpcResumeSession repo req = do
    let uid = UserId (rscUserId req)
    mSid <- liftIO $ repoGetActiveSession repo uid
    case mSid of
        Just (SessionId sid) -> do
            liftIO $ repoTouchSession repo (SessionId sid)
            pure (RpcSessionResp sid)
        Nothing -> do
            (SessionId sid, _tok) <- liftIO $ repoCreateSession repo uid
            pure (RpcSessionResp sid)

-- -----------------------------------------------------------------
-- Command execution handler
-- -----------------------------------------------------------------

rpcExecute :: TopicBus CommandEvent -> ExecuteEnv -> Repository -> User -> ExecuteReq -> Handler String
rpcExecute cmdBus execEnv _repo user req = do
    let cmdStr = erCommand req
        Username uname = userName user
    output <- liftIO $ executeCommandText execEnv user cmdStr
    liftIO $ publishCommandWithClient cmdBus RPC uname cmdStr (erClientId req)
    return output

-- -----------------------------------------------------------------
-- X-Session-Id middleware
-- -----------------------------------------------------------------

-- | WAI middleware that extracts the X-Session-Id header from incoming
-- requests and touches the session (keep-alive). This runs before
-- Servant routing, so all RPC endpoints get automatic session tracking.
sessionMiddleware :: Repository -> Middleware
sessionMiddleware repo app req sendResponse = do
    case lookup "X-Session-Id" (requestHeaders req) of
        Just bs -> case readMaybe (BS8.unpack bs) of
            Just sid -> repoTouchSession repo (SessionId sid)
            Nothing  -> pure ()
        Nothing -> pure ()
    app req sendResponse
