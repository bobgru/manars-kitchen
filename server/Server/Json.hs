{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server.Json
    ( -- * Request types (existing)
      CreateDraftReq(..)
    , GenerateDraftReq(..)
    , CommitDraftReq(..)
    , RequestAbsenceReq(..)
      -- * Response types (existing)
    , DraftCreatedResp(..)
    , FrozenDatesResp(..)
    , OverlappingDraftsResp(..)
    , DraftAssignmentsResp(..)
    , RevalidateDraftResp(..)
    , ProblemResp(..)
    , HorizonResp(..)
    , AbsenceCreatedResp(..)
      -- * Skill / Station / Shift CRUD
    , CreateSkillReq(..)
    , RenameSkillReq(..)
    , AddImplicationReq(..)
    , StationResp(..)
    , stationResp
    , CreateStationReq(..)
    , RenameStationReq(..)
    , SetStationHoursReq(..)
    , SetStationClosureReq(..)
    , CreateShiftReq(..)
      -- * Worker configuration
    , SetWorkerHoursReq(..)
    , SetWorkerOvertimeReq(..)
    , SetWorkerPrefsReq(..)
    , SetWorkerVarietyReq(..)
    , SetWorkerShiftPrefsReq(..)
    , SetWorkerWeekendOnlyReq(..)
    , SetWorkerSeniorityReq(..)
    , SetWorkerCrossTrainingReq(..)
    , SetWorkerEmploymentStatusReq(..)
    , SetWorkerOvertimeModelReq(..)
    , SetWorkerPayTrackingReq(..)
    , SetWorkerTempReq(..)
    , WorkerPairingReq(..)
      -- * Calendar / freeze
    , UnfreezeReq(..)
    , FreezeStatusResp(..)
      -- * Config
    , SetConfigReq(..)
    , SetPayPeriodReq(..)
      -- * Checkpoints
    , CreateCheckpointReq(..)
      -- * Import / Export
    , ExportResp(..)
    , ImportReq(..)
    , ImportResp(..)
      -- * Absence types
    , CreateAbsenceTypeReq(..)
    , SetAbsenceAllowanceReq(..)
      -- * Users
    , CreateUserReq(..)
    , RenameUserReq(..)
    , WorkerProfileResp(..)
    , WorkerSummaryResp(..)
    , WorkerReferencesResp(..)
    , DeactivateResultResp(..)
      -- * Hint sessions
    , AddHintReq(..)
    , HintSessionRef(..)
    , RebaseResultResp(..)
      -- * Skill references (for 409 response)
    , SkillReferencesResp(..)
      -- * Station references (for 409 response)
    , StationReferencesResp(..)
    ) where

import Data.Aeson
    ( ToJSON(..), FromJSON(..), Value, (.=), (.:), (.:?), (.!=)
    , object, withObject, withText
    )
import Data.Aeson.Types (Pair, Parser)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text, unpack)
import qualified Data.Text as T
import Data.Time
    ( Day, DayOfWeek(..), TimeOfDay(..)
    , formatTime, defaultTimeLocale, parseTimeM
    )

import Auth.Types (User(..), UserId(..), Username(..), Role(..), userIdToWorkerId)
import Domain.Types
import Domain.Skill (Skill(..))
import Domain.Shift (ShiftDef(..))
import Domain.Scheduler (ScheduleResult(..), Unfilled(..), UnfilledKind(..))
import Domain.Absence (AbsenceRequest(..), AbsenceStatus(..))
import Domain.Hint (Hint)
import Domain.Pin (PinnedAssignment(..), PinSpec(..))
import Domain.Worker (OvertimeModel(..), PayPeriodTracking(..))
import Domain.PayPeriod (PayPeriodConfig(..), PayPeriodType(..), parsePayPeriodType, showPayPeriodType)
import Export.JSON (ExportData)
import Repo.Types (DraftInfo(..), CalendarCommit(..), AuditEntry(..))
import Service.DraftValidation (DraftViolation(..))
import Service.Problems
    ( Problem(..), ProblemScope(..), Horizon(..)
    , problemWorker, problemStation, problemScope, problemSeverity
    , problemEarliestDay
    )
import qualified Service.Worker as SW

-- -----------------------------------------------------------------
-- Domain type instances
-- -----------------------------------------------------------------

instance ToJSON WorkerId where
    toJSON (WorkerId i) = toJSON i

instance FromJSON WorkerId where
    parseJSON v = WorkerId <$> parseJSON v

instance ToJSON StationId where
    toJSON (StationId i) = toJSON i

instance FromJSON StationId where
    parseJSON v = StationId <$> parseJSON v

instance ToJSON SkillId where
    toJSON (SkillId i) = toJSON i

instance FromJSON SkillId where
    parseJSON v = SkillId <$> parseJSON v

instance ToJSON AbsenceId where
    toJSON (AbsenceId i) = toJSON i

instance FromJSON AbsenceId where
    parseJSON v = AbsenceId <$> parseJSON v

instance ToJSON AbsenceTypeId where
    toJSON (AbsenceTypeId i) = toJSON i

instance FromJSON AbsenceTypeId where
    parseJSON v = AbsenceTypeId <$> parseJSON v

-- | Slot serialized as {date, start, duration}
instance ToJSON Slot where
    toJSON s = object
        [ "date"     .= formatTime defaultTimeLocale "%Y-%m-%d" (slotDate s)
        , "start"    .= formatTime defaultTimeLocale "%H:%M" (slotStart s)
        , "duration" .= (round (toRational (slotDuration s)) :: Int)
        ]

instance FromJSON Slot where
    parseJSON = withObject "Slot" $ \v -> do
        dateStr <- v .: "date"
        startStr <- v .: "start"
        dur <- v .: "duration"
        day <- maybe (fail "invalid date") pure (parseDay dateStr)
        tod <- maybe (fail "invalid time") pure (parseTime startStr)
        pure $ Slot day tod (fromIntegral (dur :: Int))

instance ToJSON Assignment where
    toJSON a = object
        [ "worker"  .= assignWorker a
        , "station" .= assignStation a
        , "slot"    .= assignSlot a
        ]

instance FromJSON Assignment where
    parseJSON = withObject "Assignment" $ \v ->
        Assignment <$> v .: "worker" <*> v .: "station" <*> v .: "slot"

instance ToJSON Schedule where
    toJSON (Schedule s) = toJSON (Set.toList s)

instance FromJSON Schedule where
    parseJSON v = Schedule . Set.fromList <$> parseJSON v

-- | Skill serialized as {name, description}
instance ToJSON Skill where
    toJSON s = object
        [ "name"        .= skillName s
        , "description" .= skillDescription s
        ]

instance FromJSON Skill where
    parseJSON = withObject "Skill" $ \v ->
        Skill <$> v .: "name" <*> v .: "description"

-- | Station serialized as {name, minStaff, maxStaff}
instance ToJSON Station where
    toJSON s = object
        [ "name"     .= stationName s
        , "minStaff" .= stationMinStaff s
        , "maxStaff" .= stationMaxStaff s
        ]

instance FromJSON Station where
    parseJSON = withObject "Station" $ \v ->
        Station <$> v .: "name" <*> v .: "minStaff" <*> v .: "maxStaff"

-- | A station as returned by @GET \/api\/stations@: the domain 'Station' plus its
--   storage id.
--
--   The id is not part of 'Station' because the scheduler compares stations by
--   value, and it is not an address — every station endpoint is name-keyed. It
--   exists so a client can resolve the numeric @station@ field of an
--   'Assignment' to a name.
data StationResp = StationResp
    { stnId       :: !Int
    , stnName     :: !Text
    , stnMinStaff :: !Int
    , stnMaxStaff :: !Int
    } deriving (Show, Eq)

instance ToJSON StationResp where
    toJSON s = object
        [ "id"       .= stnId s
        , "name"     .= stnName s
        , "minStaff" .= stnMinStaff s
        , "maxStaff" .= stnMaxStaff s
        ]

instance FromJSON StationResp where
    parseJSON = withObject "StationResp" $ \v ->
        StationResp <$> v .: "id" <*> v .: "name" <*> v .: "minStaff" <*> v .: "maxStaff"

-- | Pair a station with its id for the list endpoint.
stationResp :: StationId -> Station -> StationResp
stationResp (StationId i) st = StationResp
    { stnId       = i
    , stnName     = stationName st
    , stnMinStaff = stationMinStaff st
    , stnMaxStaff = stationMaxStaff st
    }

-- | ShiftDef serialized as {name, start, end}
instance ToJSON ShiftDef where
    toJSON s = object
        [ "name"  .= sdName s
        , "start" .= sdStart s
        , "end"   .= sdEnd s
        ]

instance FromJSON ShiftDef where
    parseJSON = withObject "ShiftDef" $ \v ->
        ShiftDef <$> v .: "name" <*> v .: "start" <*> v .: "end"

-- Note: DiffTime already has ToJSON/FromJSON from aeson

-- -----------------------------------------------------------------
-- Scheduler result types
-- -----------------------------------------------------------------

instance ToJSON UnfilledKind where
    toJSON TrulyUnfilled = "truly_unfilled"
    toJSON Understaffed  = "understaffed"

instance FromJSON UnfilledKind where
    parseJSON = withText "UnfilledKind" $ \t -> case t of
        "truly_unfilled" -> pure TrulyUnfilled
        "understaffed"   -> pure Understaffed
        _                -> fail ("unknown unfilled kind: " ++ unpack t)

instance ToJSON Unfilled where
    toJSON u = object
        [ "station" .= unfilledStation u
        , "slot"    .= unfilledSlot u
        , "kind"    .= unfilledKind u
        ]

instance FromJSON Unfilled where
    parseJSON = withObject "Unfilled" $ \v ->
        Unfilled <$> v .: "station" <*> v .: "slot" <*> v .: "kind"

instance ToJSON ScheduleResult where
    toJSON r = object
        [ "schedule" .= srSchedule r
        , "unfilled" .= srUnfilled r
        , "overtime" .= Map.mapKeys (\(WorkerId i) -> show i) (srOvertime r)
        ]

instance FromJSON ScheduleResult where
    parseJSON = withObject "ScheduleResult" $ \v -> do
        s <- v .: "schedule"
        u <- v .: "unfilled"
        otMap <- v .: "overtime"
        let ot = Map.mapKeys (\k -> WorkerId (read k :: Int)) otMap
        pure (ScheduleResult s u ot)

-- -----------------------------------------------------------------
-- Absence types
-- -----------------------------------------------------------------

instance ToJSON AbsenceStatus where
    toJSON Pending  = "pending"
    toJSON Approved = "approved"
    toJSON Rejected = "rejected"

instance FromJSON AbsenceStatus where
    parseJSON = withText "AbsenceStatus" $ \t -> case t of
        "pending"  -> pure Pending
        "approved" -> pure Approved
        "rejected" -> pure Rejected
        _          -> fail ("unknown absence status: " ++ unpack t)

instance ToJSON AbsenceRequest where
    toJSON r = object
        [ "id"      .= arId r
        , "worker"  .= arWorker r
        , "type"    .= arType r
        , "from"    .= formatTime defaultTimeLocale "%Y-%m-%d" (arStartDay r)
        , "to"      .= formatTime defaultTimeLocale "%Y-%m-%d" (arEndDay r)
        , "status"  .= arStatus r
        ]

instance FromJSON AbsenceRequest where
    parseJSON = withObject "AbsenceRequest" $ \v -> do
        i <- v .: "id"
        w <- v .: "worker"
        t <- v .: "type"
        fStr <- v .: "from"
        tStr <- v .: "to"
        s <- v .: "status"
        f <- maybe (fail "invalid from date") pure (parseDay fStr)
        to' <- maybe (fail "invalid to date") pure (parseDay tStr)
        pure (AbsenceRequest i w t f to' s)

-- -----------------------------------------------------------------
-- Repo types
-- -----------------------------------------------------------------

instance ToJSON DraftInfo where
    toJSON d = object
        [ "id"              .= diId d
        , "dateFrom"        .= formatTime defaultTimeLocale "%Y-%m-%d" (diDateFrom d)
        , "dateTo"          .= formatTime defaultTimeLocale "%Y-%m-%d" (diDateTo d)
        , "createdAt"       .= diCreatedAt d
        , "lastValidatedAt" .= diLastValidatedAt d
        ]

instance FromJSON DraftInfo where
    parseJSON = withObject "DraftInfo" $ \v -> do
        i <- v .: "id"
        dfStr <- v .: "dateFrom"
        dtStr <- v .: "dateTo"
        df <- maybe (fail "invalid dateFrom") pure (parseDay dfStr)
        dt <- maybe (fail "invalid dateTo") pure (parseDay dtStr)
        ca <- v .: "createdAt"
        lv <- v .: "lastValidatedAt"
        pure (DraftInfo i df dt ca lv)

instance ToJSON CalendarCommit where
    toJSON c = object
        [ "id"          .= ccId c
        , "committedAt" .= ccCommittedAt c
        , "dateFrom"    .= formatTime defaultTimeLocale "%Y-%m-%d" (ccDateFrom c)
        , "dateTo"      .= formatTime defaultTimeLocale "%Y-%m-%d" (ccDateTo c)
        , "note"        .= ccNote c
        -- Null for a commit that did not come from a draft, or predates the
        -- column. A client must treat it as optional.
        , "draftId"     .= ccDraftId c
        ]

instance FromJSON CalendarCommit where
    parseJSON = withObject "CalendarCommit" $ \v -> do
        i <- v .: "id"
        ca <- v .: "committedAt"
        dfStr <- v .: "dateFrom"
        dtStr <- v .: "dateTo"
        df <- maybe (fail "invalid dateFrom") pure (parseDay dfStr)
        dt <- maybe (fail "invalid dateTo") pure (parseDay dtStr)
        n <- v .: "note"
        mdid <- v .:? "draftId"
        pure (CalendarCommit i ca df dt n mdid)

-- -----------------------------------------------------------------
-- Request body types
-- -----------------------------------------------------------------

data CreateDraftReq = CreateDraftReq
    { cdrDateFrom :: !Day
    , cdrDateTo   :: !Day
    } deriving (Show)

instance ToJSON CreateDraftReq where
    toJSON r = object ["dateFrom" .= cdrDateFrom r, "dateTo" .= cdrDateTo r]

instance FromJSON CreateDraftReq where
    parseJSON = withObject "CreateDraftReq" $ \v ->
        CreateDraftReq <$> v .: "dateFrom" <*> v .: "dateTo"

-- | @workerIds@ is optional: absent means "the active workers", resolved in
-- 'Service.Draft.generateDraft'. A caller that wants the default should omit the
-- key rather than send an empty list, which means "nobody".
data GenerateDraftReq = GenerateDraftReq
    { gdrWorkerIds :: !(Maybe [Int])
    } deriving (Show)

instance ToJSON GenerateDraftReq where
    toJSON r = object ["workerIds" .= gdrWorkerIds r]

instance FromJSON GenerateDraftReq where
    parseJSON = withObject "GenerateDraftReq" $ \v ->
        GenerateDraftReq <$> v .:? "workerIds"

data CommitDraftReq = CommitDraftReq
    { cmrNote :: !T.Text
    } deriving (Show)

instance ToJSON CommitDraftReq where
    toJSON r = object ["note" .= cmrNote r]

instance FromJSON CommitDraftReq where
    parseJSON = withObject "CommitDraftReq" $ \v ->
        CommitDraftReq <$> v .: "note"

data RequestAbsenceReq = RequestAbsenceReq
    { rarWorkerId :: !Int
    , rarTypeId   :: !Int
    , rarFrom     :: !Day
    , rarTo       :: !Day
    } deriving (Show)

instance ToJSON RequestAbsenceReq where
    toJSON r = object
        [ "workerId" .= rarWorkerId r, "typeId" .= rarTypeId r
        , "from" .= rarFrom r, "to" .= rarTo r
        ]

instance FromJSON RequestAbsenceReq where
    parseJSON = withObject "RequestAbsenceReq" $ \v ->
        RequestAbsenceReq <$> v .: "workerId" <*> v .: "typeId"
                          <*> v .: "from" <*> v .: "to"

-- -----------------------------------------------------------------
-- Response types
-- -----------------------------------------------------------------

data DraftCreatedResp = DraftCreatedResp
    { dcrId :: !Int
    } deriving (Show, Eq)

instance ToJSON DraftCreatedResp where
    toJSON r = object ["id" .= dcrId r]

instance FromJSON DraftCreatedResp where
    parseJSON = withObject "DraftCreatedResp" $ \v ->
        DraftCreatedResp <$> v .: "id"

-- | 409 body for a draft creation refused by the freeze line.
--
-- Carries @error@ so that a client which only reads that key still shows
-- something useful, and the three dates so that a client can name the range or
-- offer an unfreeze affordance later. Neither force nor unfreeze is reachable
-- over HTTP, so this is terminal for a REST caller.
data FrozenDatesResp = FrozenDatesResp
    { fdrError      :: !T.Text
    , fdrFreezeLine :: !Day
    , fdrFrozenFrom :: !Day
    , fdrFrozenTo   :: !Day
    } deriving (Show, Eq)

instance ToJSON FrozenDatesResp where
    toJSON r = object
        [ "error"      .= fdrError r
        , "freezeLine" .= fdrFreezeLine r
        , "frozenFrom" .= fdrFrozenFrom r
        , "frozenTo"   .= fdrFrozenTo r
        ]

instance FromJSON FrozenDatesResp where
    parseJSON = withObject "FrozenDatesResp" $ \v ->
        FrozenDatesResp
            <$> v .: "error"
            <*> v .: "freezeLine"
            <*> v .: "frozenFrom"
            <*> v .: "frozenTo"

-- | 409 body for a commit refused because another draft covers the same dates.
--
-- Carries @error@ for a client that reads only that key, and the sibling drafts
-- in full so a client can list them and offer the force affordance —
-- @POST \/api\/drafts\/:id\/commit\/force@ — without a second round trip.
data OverlappingDraftsResp = OverlappingDraftsResp
    { odrError  :: !T.Text
    , odrDrafts :: ![DraftInfo]
    } deriving (Show, Eq)

instance ToJSON OverlappingDraftsResp where
    toJSON r = object
        [ "error"  .= odrError r
        , "drafts" .= odrDrafts r
        ]

instance FromJSON OverlappingDraftsResp where
    parseJSON = withObject "OverlappingDraftsResp" $ \v ->
        OverlappingDraftsResp <$> v .: "error" <*> v .: "drafts"

-- | A constraint violation, as reported to a reader.
--
-- @constraint@ is the short label the CLI groups by ("absence conflict") and
-- @reason@ the sentence explaining it. Both are already user-facing strings, so
-- neither is a code a client should switch on.
instance ToJSON DraftViolation where
    toJSON v = object
        [ "assignment" .= dvAssignment v
        , "constraint" .= dvConstraint v
        , "reason"     .= dvReason v
        ]

instance FromJSON DraftViolation where
    parseJSON = withObject "DraftViolation" $ \v ->
        DraftViolation <$> v .: "assignment" <*> v .: "constraint"
                       <*> v .: "reason"

-- | What a draft holds and what is wrong with it, without changing either.
--
-- @violations@ comes from 'Service.DraftValidation.computeDraftViolations', so
-- the assignments it names are still present in @assignments@ — this is a report,
-- not a diff. @replacedUnder@ is the calendar commits that overwrote part of this
-- draft's own date range since it was last validated; it is here because a read
-- that reported violations while staying silent about the baseline moving would
-- mislead in exactly the case ADR 0003 made common.
data DraftAssignmentsResp = DraftAssignmentsResp
    { darAssignments   :: !Schedule
    , darViolations    :: ![DraftViolation]
    , darReplacedUnder :: ![CalendarCommit]
    } deriving (Show)

instance ToJSON DraftAssignmentsResp where
    toJSON r = object
        [ "assignments"   .= darAssignments r
        , "violations"    .= darViolations r
        , "replacedUnder" .= darReplacedUnder r
        ]

instance FromJSON DraftAssignmentsResp where
    parseJSON = withObject "DraftAssignmentsResp" $ \v ->
        DraftAssignmentsResp
            <$> v .: "assignments"
            <*> v .: "violations"
            <*> v .: "replacedUnder"

-- | What an explicit revalidate removed. Named @removed@ rather than
-- @violations@ because these assignments are gone from the draft, which is the
-- whole difference between this and the GET.
data RevalidateDraftResp = RevalidateDraftResp
    { rvrRemoved :: ![DraftViolation]
    } deriving (Show)

instance ToJSON RevalidateDraftResp where
    toJSON r = object ["removed" .= rvrRemoved r]

instance FromJSON RevalidateDraftResp where
    parseJSON = withObject "RevalidateDraftResp" $ \v ->
        RevalidateDraftResp <$> v .: "removed"

data AbsenceCreatedResp = AbsenceCreatedResp
    { acrId :: !Int
    } deriving (Show, Eq)

instance ToJSON AbsenceCreatedResp where
    toJSON r = object ["id" .= acrId r]

instance FromJSON AbsenceCreatedResp where
    parseJSON = withObject "AbsenceCreatedResp" $ \v ->
        AbsenceCreatedResp <$> v .: "id"

-- -----------------------------------------------------------------
-- Auth types
-- -----------------------------------------------------------------

instance ToJSON UserId where
    toJSON (UserId i) = toJSON i

instance FromJSON UserId where
    parseJSON v = UserId <$> parseJSON v

instance ToJSON Username where
    toJSON (Username s) = toJSON s

instance FromJSON Username where
    parseJSON v = Username <$> parseJSON v

instance ToJSON Role where
    toJSON Admin  = "admin"
    toJSON Normal = "normal"

instance FromJSON Role where
    parseJSON = withText "Role" $ \t -> case t of
        "admin"  -> pure Admin
        "normal" -> pure Normal
        _        -> fail ("unknown role: " ++ unpack t)

instance ToJSON User where
    toJSON u = object
        [ "id"            .= userId u
        , "username"      .= userName u
        , "role"          .= userRole u
        , "workerId"      .= userIdToWorkerId (userId u)
        , "workerStatus"  .= workerStatusToText (userWorkerStatus u)
        , "deactivatedAt" .= fmap show (userDeactivatedAt u)
        ]

instance FromJSON User where
    parseJSON = withObject "User" $ \v -> do
        i <- v .: "id"
        n <- v .: "username"
        r <- v .: "role"
        ws <- v .:? "workerStatus" .!= "active"
        let status = case textToWorkerStatus ws of
                Just s  -> s
                Nothing -> WSActive
        return $ User i n "" r status Nothing

-- -----------------------------------------------------------------
-- Pin types
-- -----------------------------------------------------------------

instance ToJSON PinSpec where
    toJSON (PinSlot h) = object ["type" .= ("slot" :: String), "hour" .= h]
    toJSON (PinShift n) = object ["type" .= ("shift" :: String), "name" .= n]

instance FromJSON PinSpec where
    parseJSON = withObject "PinSpec" $ \v -> do
        t <- v .: "type" :: Data.Aeson.Types.Parser String
        case t of
            "slot"  -> PinSlot <$> v .: "hour"
            "shift" -> PinShift <$> v .: "name"
            _       -> fail ("unknown pin spec type: " ++ t)

instance ToJSON PinnedAssignment where
    toJSON p = object
        [ "worker"  .= pinWorker p
        , "station" .= pinStation p
        , "day"     .= pinDay p
        , "spec"    .= pinSpec p
        ]

instance FromJSON PinnedAssignment where
    parseJSON = withObject "PinnedAssignment" $ \v ->
        PinnedAssignment <$> v .: "worker" <*> v .: "station"
                         <*> v .: "day" <*> v .: "spec"

-- -----------------------------------------------------------------
-- Employment types
-- -----------------------------------------------------------------

instance ToJSON OvertimeModel where
    toJSON OTEligible  = "eligible"
    toJSON OTManualOnly = "manual-only"
    toJSON OTExempt    = "exempt"

instance FromJSON OvertimeModel where
    parseJSON = withText "OvertimeModel" $ \t -> case t of
        "eligible"    -> pure OTEligible
        "manual-only" -> pure OTManualOnly
        "exempt"      -> pure OTExempt
        _             -> fail ("unknown overtime model: " ++ unpack t)

instance ToJSON PayPeriodTracking where
    toJSON PPStandard = "standard"
    toJSON PPExempt   = "exempt"

instance FromJSON PayPeriodTracking where
    parseJSON = withText "PayPeriodTracking" $ \t -> case t of
        "standard" -> pure PPStandard
        "exempt"   -> pure PPExempt
        _          -> fail ("unknown pay period tracking: " ++ unpack t)

instance ToJSON PayPeriodType where
    toJSON = toJSON . showPayPeriodType

instance FromJSON PayPeriodType where
    parseJSON = withText "PayPeriodType" $ \t ->
        case parsePayPeriodType (unpack t) of
            Just pt -> pure pt
            Nothing -> fail ("unknown pay period type: " ++ unpack t)

instance ToJSON PayPeriodConfig where
    toJSON c = object
        [ "type"       .= ppcType c
        , "anchorDate" .= ppcAnchorDate c
        ]

instance FromJSON PayPeriodConfig where
    parseJSON = withObject "PayPeriodConfig" $ \v ->
        PayPeriodConfig <$> v .: "type" <*> v .: "anchorDate"

-- -----------------------------------------------------------------
-- Audit entry
-- -----------------------------------------------------------------

instance ToJSON AuditEntry where
    toJSON e = object
        [ "id"         .= aeId e
        , "timestamp"  .= aeTimestamp e
        , "username"   .= aeUsername e
        , "command"    .= aeCommand e
        , "entityType" .= aeEntityType e
        , "operation"  .= aeOperation e
        , "entityId"   .= aeEntityId e
        , "targetId"   .= aeTargetId e
        , "dateFrom"   .= aeDateFrom e
        , "dateTo"     .= aeDateTo e
        , "isMutation" .= aeIsMutation e
        , "params"     .= aeParams e
        , "source"     .= aeSource e
        ]

instance FromJSON AuditEntry where
    parseJSON = withObject "AuditEntry" $ \v ->
        AuditEntry <$> v .: "id" <*> v .: "timestamp" <*> v .: "username"
                   <*> v .:? "command" <*> v .:? "entityType" <*> v .:? "operation"
                   <*> v .:? "entityId" <*> v .:? "targetId"
                   <*> v .:? "dateFrom" <*> v .:? "dateTo"
                   <*> v .: "isMutation" <*> v .:? "params" <*> v .: "source"

-- -----------------------------------------------------------------
-- Skill / Station / Shift CRUD requests
-- -----------------------------------------------------------------

data CreateSkillReq = CreateSkillReq
    { csrName        :: !T.Text
    , csrDescription :: !T.Text
    } deriving (Show)

instance ToJSON CreateSkillReq where
    toJSON r = object ["name" .= csrName r, "description" .= csrDescription r]

instance FromJSON CreateSkillReq where
    parseJSON = withObject "CreateSkillReq" $ \v ->
        CreateSkillReq <$> v .: "name" <*> v .: "description"

data RenameSkillReq = RenameSkillReq
    { rsrName :: !T.Text
    } deriving (Show)

instance ToJSON RenameSkillReq where
    toJSON r = object ["name" .= rsrName r]

instance FromJSON RenameSkillReq where
    parseJSON = withObject "RenameSkillReq" $ \v ->
        RenameSkillReq <$> v .: "name"

data AddImplicationReq = AddImplicationReq
    { airImpliesSkillName :: !String
    } deriving (Show)

instance ToJSON AddImplicationReq where
    toJSON r = object ["impliesSkillName" .= airImpliesSkillName r]

instance FromJSON AddImplicationReq where
    parseJSON = withObject "AddImplicationReq" $ \v ->
        AddImplicationReq <$> v .: "impliesSkillName"

data CreateStationReq = CreateStationReq
    { cstrName     :: !Text
    , cstrMinStaff :: !Int
    , cstrMaxStaff :: !Int
    } deriving (Show)

instance ToJSON CreateStationReq where
    toJSON r = object ["name" .= cstrName r, "minStaff" .= cstrMinStaff r, "maxStaff" .= cstrMaxStaff r]

instance FromJSON CreateStationReq where
    parseJSON = withObject "CreateStationReq" $ \v ->
        CreateStationReq <$> v .: "name" <*> (v .:? "minStaff" .!= (1 :: Int)) <*> (v .:? "maxStaff" .!= (1 :: Int))

data RenameStationReq = RenameStationReq
    { rstrName :: !Text
    } deriving (Show)

instance ToJSON RenameStationReq where
    toJSON r = object ["name" .= rstrName r]

instance FromJSON RenameStationReq where
    parseJSON = withObject "RenameStationReq" $ \v ->
        RenameStationReq <$> v .: "name"

data SetStationHoursReq = SetStationHoursReq
    { sshrStart :: !Int
    , sshrEnd   :: !Int
    } deriving (Show)

instance ToJSON SetStationHoursReq where
    toJSON r = object ["start" .= sshrStart r, "end" .= sshrEnd r]

instance FromJSON SetStationHoursReq where
    parseJSON = withObject "SetStationHoursReq" $ \v ->
        SetStationHoursReq <$> v .: "start" <*> v .: "end"

data SetStationClosureReq = SetStationClosureReq
    { sscrDay :: !DayOfWeek
    } deriving (Show)

instance ToJSON SetStationClosureReq where
    toJSON r = object ["day" .= sscrDay r]

instance FromJSON SetStationClosureReq where
    parseJSON = withObject "SetStationClosureReq" $ \v ->
        SetStationClosureReq <$> v .: "day"

data CreateShiftReq = CreateShiftReq
    { cshrName  :: !String
    , cshrStart :: !Int
    , cshrEnd   :: !Int
    } deriving (Show)

instance ToJSON CreateShiftReq where
    toJSON r = object ["name" .= cshrName r, "start" .= cshrStart r, "end" .= cshrEnd r]

instance FromJSON CreateShiftReq where
    parseJSON = withObject "CreateShiftReq" $ \v ->
        CreateShiftReq <$> v .: "name" <*> v .: "start" <*> v .: "end"

-- -----------------------------------------------------------------
-- Worker configuration requests
-- -----------------------------------------------------------------

data SetWorkerHoursReq = SetWorkerHoursReq
    { swhrHours :: !Int
    } deriving (Show)

instance ToJSON SetWorkerHoursReq where
    toJSON r = object ["hours" .= swhrHours r]

instance FromJSON SetWorkerHoursReq where
    parseJSON = withObject "SetWorkerHoursReq" $ \v ->
        SetWorkerHoursReq <$> v .: "hours"

data SetWorkerOvertimeReq = SetWorkerOvertimeReq
    { sworOptIn :: !Bool
    } deriving (Show)

instance ToJSON SetWorkerOvertimeReq where
    toJSON r = object ["optIn" .= sworOptIn r]

instance FromJSON SetWorkerOvertimeReq where
    parseJSON = withObject "SetWorkerOvertimeReq" $ \v ->
        SetWorkerOvertimeReq <$> v .: "optIn"

data SetWorkerPrefsReq = SetWorkerPrefsReq
    { swprStationIds :: ![Int]
    } deriving (Show)

instance ToJSON SetWorkerPrefsReq where
    toJSON r = object ["stationIds" .= swprStationIds r]

instance FromJSON SetWorkerPrefsReq where
    parseJSON = withObject "SetWorkerPrefsReq" $ \v ->
        SetWorkerPrefsReq <$> v .: "stationIds"

data SetWorkerVarietyReq = SetWorkerVarietyReq
    { swvrPrefer :: !Bool
    } deriving (Show)

instance ToJSON SetWorkerVarietyReq where
    toJSON r = object ["prefer" .= swvrPrefer r]

instance FromJSON SetWorkerVarietyReq where
    parseJSON = withObject "SetWorkerVarietyReq" $ \v ->
        SetWorkerVarietyReq <$> v .: "prefer"

data SetWorkerShiftPrefsReq = SetWorkerShiftPrefsReq
    { swsprShifts :: ![String]
    } deriving (Show)

instance ToJSON SetWorkerShiftPrefsReq where
    toJSON r = object ["shifts" .= swsprShifts r]

instance FromJSON SetWorkerShiftPrefsReq where
    parseJSON = withObject "SetWorkerShiftPrefsReq" $ \v ->
        SetWorkerShiftPrefsReq <$> v .: "shifts"

data SetWorkerWeekendOnlyReq = SetWorkerWeekendOnlyReq
    { swwoVal :: !Bool
    } deriving (Show)

instance ToJSON SetWorkerWeekendOnlyReq where
    toJSON r = object ["weekendOnly" .= swwoVal r]

instance FromJSON SetWorkerWeekendOnlyReq where
    parseJSON = withObject "SetWorkerWeekendOnlyReq" $ \v ->
        SetWorkerWeekendOnlyReq <$> v .: "weekendOnly"

data SetWorkerSeniorityReq = SetWorkerSeniorityReq
    { swsrLevel :: !Int
    } deriving (Show)

instance ToJSON SetWorkerSeniorityReq where
    toJSON r = object ["level" .= swsrLevel r]

instance FromJSON SetWorkerSeniorityReq where
    parseJSON = withObject "SetWorkerSeniorityReq" $ \v ->
        SetWorkerSeniorityReq <$> v .: "level"

data SetWorkerCrossTrainingReq = SetWorkerCrossTrainingReq
    { swctrSkillId :: !Int
    } deriving (Show)

instance ToJSON SetWorkerCrossTrainingReq where
    toJSON r = object ["skillId" .= swctrSkillId r]

instance FromJSON SetWorkerCrossTrainingReq where
    parseJSON = withObject "SetWorkerCrossTrainingReq" $ \v ->
        SetWorkerCrossTrainingReq <$> v .: "skillId"

data SetWorkerEmploymentStatusReq = SetWorkerEmploymentStatusReq
    { swesStatus :: !String
    } deriving (Show)

instance ToJSON SetWorkerEmploymentStatusReq where
    toJSON r = object ["status" .= swesStatus r]

instance FromJSON SetWorkerEmploymentStatusReq where
    parseJSON = withObject "SetWorkerEmploymentStatusReq" $ \v ->
        SetWorkerEmploymentStatusReq <$> v .: "status"

data SetWorkerOvertimeModelReq = SetWorkerOvertimeModelReq
    { swomModel :: !OvertimeModel
    } deriving (Show)

instance ToJSON SetWorkerOvertimeModelReq where
    toJSON r = object ["model" .= swomModel r]

instance FromJSON SetWorkerOvertimeModelReq where
    parseJSON = withObject "SetWorkerOvertimeModelReq" $ \v ->
        SetWorkerOvertimeModelReq <$> v .: "model"

data SetWorkerPayTrackingReq = SetWorkerPayTrackingReq
    { swptTracking :: !PayPeriodTracking
    } deriving (Show)

instance ToJSON SetWorkerPayTrackingReq where
    toJSON r = object ["tracking" .= swptTracking r]

instance FromJSON SetWorkerPayTrackingReq where
    parseJSON = withObject "SetWorkerPayTrackingReq" $ \v ->
        SetWorkerPayTrackingReq <$> v .: "tracking"

data SetWorkerTempReq = SetWorkerTempReq
    { swtTemp :: !Bool
    } deriving (Show)

instance ToJSON SetWorkerTempReq where
    toJSON r = object ["temp" .= swtTemp r]

instance FromJSON SetWorkerTempReq where
    parseJSON = withObject "SetWorkerTempReq" $ \v ->
        SetWorkerTempReq <$> v .: "temp"

data WorkerPairingReq = WorkerPairingReq
    { wprOtherWorkerId :: !Int
    } deriving (Show)

instance ToJSON WorkerPairingReq where
    toJSON r = object ["otherWorkerId" .= wprOtherWorkerId r]

instance FromJSON WorkerPairingReq where
    parseJSON = withObject "WorkerPairingReq" $ \v ->
        WorkerPairingReq <$> v .: "otherWorkerId"

-- -----------------------------------------------------------------
-- Calendar / Freeze
-- -----------------------------------------------------------------

data UnfreezeReq = UnfreezeReq
    { ufFrom :: !Day
    , ufTo   :: !Day
    } deriving (Show)

instance ToJSON UnfreezeReq where
    toJSON r = object ["from" .= ufFrom r, "to" .= ufTo r]

instance FromJSON UnfreezeReq where
    parseJSON = withObject "UnfreezeReq" $ \v ->
        UnfreezeReq <$> v .: "from" <*> v .: "to"

data FreezeStatusResp = FreezeStatusResp
    { fsFreezeLine :: !Day
    } deriving (Show)

instance ToJSON FreezeStatusResp where
    toJSON r = object ["freezeLine" .= fsFreezeLine r]

instance FromJSON FreezeStatusResp where
    parseJSON = withObject "FreezeStatusResp" $ \v ->
        FreezeStatusResp <$> v .: "freezeLine"

-- -----------------------------------------------------------------
-- Config writes
-- -----------------------------------------------------------------

data SetConfigReq = SetConfigReq
    { scrValue :: !Double
    } deriving (Show)

instance ToJSON SetConfigReq where
    toJSON r = object ["value" .= scrValue r]

instance FromJSON SetConfigReq where
    parseJSON = withObject "SetConfigReq" $ \v ->
        SetConfigReq <$> v .: "value"

data SetPayPeriodReq = SetPayPeriodReq
    { sprType       :: !String
    , sprAnchorDate :: !Day
    } deriving (Show)

instance ToJSON SetPayPeriodReq where
    toJSON r = object ["type" .= sprType r, "anchorDate" .= sprAnchorDate r]

instance FromJSON SetPayPeriodReq where
    parseJSON = withObject "SetPayPeriodReq" $ \v ->
        SetPayPeriodReq <$> v .: "type" <*> v .: "anchorDate"

-- -----------------------------------------------------------------
-- Checkpoint requests
-- -----------------------------------------------------------------

data CreateCheckpointReq = CreateCheckpointReq
    { ccrName :: !T.Text
    } deriving (Show)

instance ToJSON CreateCheckpointReq where
    toJSON r = object ["name" .= ccrName r]

instance FromJSON CreateCheckpointReq where
    parseJSON = withObject "CreateCheckpointReq" $ \v ->
        CreateCheckpointReq <$> v .: "name"

-- -----------------------------------------------------------------
-- Import / Export
-- -----------------------------------------------------------------

newtype ExportResp = ExportResp { erData :: ExportData }
    deriving (Show)

instance ToJSON ExportResp where
    toJSON r = toJSON (erData r)

instance FromJSON ExportResp where
    parseJSON v = ExportResp <$> parseJSON v

newtype ImportReq = ImportReq { irData :: ExportData }
    deriving (Show)

instance ToJSON ImportReq where
    toJSON r = toJSON (irData r)

instance FromJSON ImportReq where
    parseJSON v = ImportReq <$> parseJSON v

data ImportResp = ImportResp
    { irMessages :: ![String]
    } deriving (Show)

instance ToJSON ImportResp where
    toJSON r = object ["messages" .= irMessages r]

instance FromJSON ImportResp where
    parseJSON = withObject "ImportResp" $ \v ->
        ImportResp <$> v .: "messages"

-- -----------------------------------------------------------------
-- Absence type management
-- -----------------------------------------------------------------

data CreateAbsenceTypeReq = CreateAbsenceTypeReq
    { catrName        :: !Text
    , catrCountsAgainstAllowance :: !Bool
    } deriving (Show)

instance ToJSON CreateAbsenceTypeReq where
    toJSON r = object
        [ "name" .= catrName r
        , "countsAgainstAllowance" .= catrCountsAgainstAllowance r
        ]

instance FromJSON CreateAbsenceTypeReq where
    parseJSON = withObject "CreateAbsenceTypeReq" $ \v ->
        CreateAbsenceTypeReq <$> v .: "name"
                             <*> v .: "countsAgainstAllowance"

data SetAbsenceAllowanceReq = SetAbsenceAllowanceReq
    { saarWorkerId  :: !Int
    , saarAllowance :: !Int
    } deriving (Show)

instance ToJSON SetAbsenceAllowanceReq where
    toJSON r = object ["workerId" .= saarWorkerId r, "allowance" .= saarAllowance r]

instance FromJSON SetAbsenceAllowanceReq where
    parseJSON = withObject "SetAbsenceAllowanceReq" $ \v ->
        SetAbsenceAllowanceReq <$> v .: "workerId" <*> v .: "allowance"

-- -----------------------------------------------------------------
-- User management
-- -----------------------------------------------------------------

data CreateUserReq = CreateUserReq
    { curUsername :: !T.Text
    , curPassword :: !T.Text
    , curRole     :: !Role
    , curNoWorker :: !Bool
    } deriving (Show)

instance ToJSON CreateUserReq where
    toJSON r = object
        [ "username" .= curUsername r, "password" .= curPassword r
        , "role"     .= curRole r,     "noWorker" .= curNoWorker r
        ]

instance FromJSON CreateUserReq where
    parseJSON = withObject "CreateUserReq" $ \v ->
        CreateUserReq <$> v .: "username" <*> v .: "password"
                      <*> v .: "role" <*> v .:? "noWorker" .!= False

-- | Request body for renaming a user (= renaming a worker).
newtype RenameUserReq = RenameUserReq { rurNewName :: T.Text }
    deriving (Show)

instance ToJSON RenameUserReq where
    toJSON r = object ["name" .= rurNewName r]

instance FromJSON RenameUserReq where
    parseJSON = withObject "RenameUserReq" $ \v ->
        RenameUserReq <$> v .: "name"

-- | Worker view profile (from Service.Worker.WorkerProfile).
data WorkerProfileResp = WorkerProfileResp
    { wprName              :: !T.Text
    , wprUserId            :: !Int
    , wprWorkerId          :: !Int
    , wprRole              :: !T.Text
    , wprStatus            :: !T.Text
    , wprDeactivatedAt     :: !(Maybe T.Text)
    , wprOvertimeModel     :: !T.Text
    , wprPayPeriodTracking :: !T.Text
    , wprIsTemp            :: !Bool
    , wprMaxPeriodHours    :: !(Maybe Int)
    , wprOvertimeOptIn     :: !Bool
    , wprWeekendOnly       :: !Bool
    , wprPrefersVariety    :: !Bool
    , wprSeniority         :: !Int
    , wprSkills            :: ![T.Text]
    , wprStationPrefs      :: ![T.Text]
    , wprShiftPrefs        :: ![T.Text]
    , wprCrossTraining     :: ![T.Text]
    , wprAvoidPairing      :: ![T.Text]
    , wprPreferPairing     :: ![T.Text]
    } deriving (Show)

instance ToJSON WorkerProfileResp where
    toJSON p = object
        [ "name"              .= wprName p
        , "userId"            .= wprUserId p
        , "workerId"          .= wprWorkerId p
        , "role"              .= wprRole p
        , "status"            .= wprStatus p
        , "deactivatedAt"     .= wprDeactivatedAt p
        , "overtimeModel"     .= wprOvertimeModel p
        , "payPeriodTracking" .= wprPayPeriodTracking p
        , "isTemp"            .= wprIsTemp p
        , "maxPeriodHours"    .= wprMaxPeriodHours p
        , "overtimeOptIn"     .= wprOvertimeOptIn p
        , "weekendOnly"       .= wprWeekendOnly p
        , "prefersVariety"    .= wprPrefersVariety p
        , "seniority"         .= wprSeniority p
        , "skills"            .= wprSkills p
        , "stationPrefs"      .= wprStationPrefs p
        , "shiftPrefs"        .= wprShiftPrefs p
        , "crossTraining"     .= wprCrossTraining p
        , "avoidPairing"      .= wprAvoidPairing p
        , "preferPairing"     .= wprPreferPairing p
        ]

-- | References blocking a 'worker delete' (mirror of Skill/StationReferencesResp).
data WorkerReferencesResp = WorkerReferencesResp
    { wrrConfiguration :: ![T.Text]
    , wrrSchedule      :: ![T.Text]
    } deriving (Show)

instance ToJSON WorkerReferencesResp where
    toJSON r = object
        [ "configuration" .= wrrConfiguration r
        , "schedule"      .= wrrSchedule r
        ]

-- | Result of a 'worker deactivate' call: counts removed.
data DeactivateResultResp = DeactivateResultResp
    { drrPinsRemoved     :: !Int
    , drrDraftsRemoved   :: !Int
    , drrCalendarRemoved :: !Int
    } deriving (Show)

instance ToJSON DeactivateResultResp where
    toJSON r = object
        [ "pinsRemoved"     .= drrPinsRemoved r
        , "draftsRemoved"   .= drrDraftsRemoved r
        , "calendarRemoved" .= drrCalendarRemoved r
        ]

instance FromJSON DeactivateResultResp where
    parseJSON = withObject "DeactivateResultResp" $ \v ->
        DeactivateResultResp <$> v .: "pinsRemoved"
                             <*> v .: "draftsRemoved"
                             <*> v .: "calendarRemoved"

instance FromJSON WorkerProfileResp where
    parseJSON = withObject "WorkerProfileResp" $ \v ->
        WorkerProfileResp
            <$> v .:  "name"
            <*> v .:  "userId"
            <*> v .:  "workerId"
            <*> v .:  "role"
            <*> v .:  "status"
            <*> v .:? "deactivatedAt"
            <*> v .:  "overtimeModel"
            <*> v .:  "payPeriodTracking"
            <*> v .:  "isTemp"
            <*> v .:? "maxPeriodHours"
            <*> v .:  "overtimeOptIn"
            <*> v .:  "weekendOnly"
            <*> v .:  "prefersVariety"
            <*> v .:  "seniority"
            <*> v .:  "skills"
            <*> v .:  "stationPrefs"
            <*> v .:  "shiftPrefs"
            <*> v .:  "crossTraining"
            <*> v .:  "avoidPairing"
            <*> v .:  "preferPairing"

-- | Slim summary row for the workers list page.
--
--   @wsrId@ is the worker's storage identifier. It is here so the client can
--   resolve the numeric @worker@ field of an 'Assignment' to a name; it is not
--   an address — every worker endpoint is name-keyed.
data WorkerSummaryResp = WorkerSummaryResp
    { wsrId          :: !Int
    , wsrName        :: !Text
    , wsrRole        :: !Text
    , wsrStatus      :: !Text
    , wsrIsTemp      :: !Bool
    , wsrWeekendOnly :: !Bool
    , wsrSeniority   :: !Int
    } deriving (Show)

instance ToJSON WorkerSummaryResp where
    toJSON r = object
        [ "id"          .= wsrId r
        , "name"        .= wsrName r
        , "role"        .= wsrRole r
        , "status"      .= wsrStatus r
        , "isTemp"      .= wsrIsTemp r
        , "weekendOnly" .= wsrWeekendOnly r
        , "seniority"   .= wsrSeniority r
        ]

instance FromJSON WorkerSummaryResp where
    parseJSON = withObject "WorkerSummaryResp" $ \v ->
        WorkerSummaryResp
            <$> v .: "id"
            <*> v .: "name"
            <*> v .: "role"
            <*> v .: "status"
            <*> v .: "isTemp"
            <*> v .: "weekendOnly"
            <*> v .: "seniority"

-- -----------------------------------------------------------------
-- Hint session types
-- -----------------------------------------------------------------

-- | Reference to a hint session (sessionId + draftId).
data HintSessionRef = HintSessionRef
    { hsrSessionId :: !Int
    , hsrDraftId   :: !Int
    } deriving (Show)

instance ToJSON HintSessionRef where
    toJSON r = object ["sessionId" .= hsrSessionId r, "draftId" .= hsrDraftId r]

instance FromJSON HintSessionRef where
    parseJSON = withObject "HintSessionRef" $ \v ->
        HintSessionRef <$> v .: "sessionId" <*> v .: "draftId"

-- | Add a hint to a session.
data AddHintReq = AddHintReq
    { ahrSessionId :: !Int
    , ahrDraftId   :: !Int
    , ahrHint      :: !Hint
    } deriving (Show)

instance ToJSON AddHintReq where
    toJSON r = object
        [ "sessionId" .= ahrSessionId r
        , "draftId"   .= ahrDraftId r
        , "hint"      .= ahrHint r
        ]

instance FromJSON AddHintReq where
    parseJSON = withObject "AddHintReq" $ \v ->
        AddHintReq <$> v .: "sessionId" <*> v .: "draftId" <*> v .: "hint"

-- | Rebase result response.
data RebaseResultResp = RebaseResultResp
    { rrrStatus  :: !String     -- ^ "up-to-date", "auto-rebase", "has-conflicts", "session-invalid"
    , rrrDetails :: !String     -- ^ Human-readable detail
    } deriving (Show, Eq)

instance ToJSON RebaseResultResp where
    toJSON r = object ["status" .= rrrStatus r, "details" .= rrrDetails r]

instance FromJSON RebaseResultResp where
    parseJSON = withObject "RebaseResultResp" $ \v ->
        RebaseResultResp <$> v .: "status" <*> v .: "details"

-- -----------------------------------------------------------------
-- Skill references (409 response for safe delete)
-- -----------------------------------------------------------------

newtype SkillReferencesResp = SkillReferencesResp SW.SkillReferences

instance ToJSON SkillReferencesResp where
    toJSON (SkillReferencesResp refs) = object
        [ "workers"       .= [object ["name" .= n] | (_, n) <- SW.srWorkers refs]
        , "stations"      .= [object ["name" .= n] | (_, n) <- SW.srStations refs]
        , "crossTraining" .= [object ["name" .= n] | (_, n) <- SW.srCrossTraining refs]
        , "impliedBy"     .= [object ["name" .= n] | (_, n) <- SW.srImpliedBy refs]
        , "implies"       .= [object ["name" .= n] | (_, n) <- SW.srImplies refs]
        ]

-- -----------------------------------------------------------------
-- Station references (409 response for safe delete)
-- -----------------------------------------------------------------

newtype StationReferencesResp = StationReferencesResp SW.StationReferences

instance ToJSON StationReferencesResp where
    toJSON (StationReferencesResp refs) = object
        [ "workerPrefs"    .= [object ["name" .= n] | (_, n) <- SW.strWorkerPrefs refs]
        , "requiredSkills" .= [object ["name" .= n] | (_, n) <- SW.strRequiredSkills refs]
        ]


-- -----------------------------------------------------------------
-- Problems
-- -----------------------------------------------------------------

-- | One problem, flattened for a client.
--
-- @kind@ is what picks the wording; @severityRank@ is what a cell aggregates on,
-- higher being more severe. Both are sent because the ordering belongs on the
-- server — a client that hardcoded it would be a second place to change when a
-- fourth kind appears. They are derived from the same constructor, so they cannot
-- disagree.
--
-- @worker@ and @station@ are nullable because not every problem has both:
-- understaffing is a station-and-slot fact with no worker at all, and an
-- unscheduled day has neither. This is the envelope the three projections in
-- ADR 0004 filter on.
newtype ProblemResp = ProblemResp Problem
    deriving (Eq, Show)

instance ToJSON ProblemResp where
    toJSON (ProblemResp p) = object
        ([ "kind"         .= problemKindName p
         , "severityRank" .= fromEnum (problemSeverity p)
         , "worker"       .= problemWorker p
         , "station"      .= problemStation p
         , "scope"        .= scopeJson (problemScope p)
         , "earliestDay"  .= problemEarliestDay p
         ] ++ problemDetail p)

problemKindName :: Problem -> Text
problemKindName (PViolation _)          = "violation"
problemKindName (PUnderstaffed _ _ _ _) = "understaffed"
problemKindName (PUnscheduled _)        = "unscheduled"

-- | The kind-specific payload. A client switches on @kind@ to know which of
-- these to read. An unscheduled day adds nothing: the day is already in @scope@,
-- and "nobody at all" has no counts to report.
problemDetail :: Problem -> [Pair]
problemDetail (PViolation v) = ["violation" .= v]
problemDetail (PUnderstaffed _ _ assigned required) =
    [ "assigned" .= assigned
    , "required" .= required
    ]
problemDetail (PUnscheduled _) = []

scopeJson :: ProblemScope -> Value
scopeJson (ScopeSlot t) = object ["kind" .= ("slot" :: Text), "slot" .= t]
scopeJson (ScopeDay d)  = object ["kind" .= ("day" :: Text), "day" .= d]

-- | Parses back what 'ToJSON' writes, dispatching on @kind@. Exists so the
-- integration suite can decode the endpoint through the servant client, and so
-- the encoding is exercised as a round trip rather than only asserted on.
instance FromJSON ProblemResp where
    parseJSON = withObject "ProblemResp" $ \v -> do
        kind <- v .: "kind" :: Parser Text
        case kind of
            "violation" -> ProblemResp . PViolation <$> v .: "violation"
            "understaffed" -> do
                st       <- v .: "station"
                scope    <- v .: "scope"
                slot     <- withObject "scope" (.: "slot") scope
                assigned <- v .: "assigned"
                required <- v .: "required"
                pure (ProblemResp (PUnderstaffed st slot assigned required))
            "unscheduled" -> do
                scope <- v .: "scope"
                day   <- withObject "scope" (.: "day") scope
                pure (ProblemResp (PUnscheduled day))
            other -> fail ("unknown problem kind: " ++ T.unpack other)

-- | One horizon the problem view can be scoped to.
--
-- @label@ is a date range rather than a word for the two pay periods, because
-- 'Domain.PayPeriod.PayPeriodType' is configurable and "this week" would be a lie
-- for a monthly-paid restaurant. Both dates are inclusive.
newtype HorizonResp = HorizonResp Horizon
    deriving (Eq, Show)

instance ToJSON HorizonResp where
    toJSON (HorizonResp h) = object
        [ "key"   .= hKey h
        , "label" .= hLabel h
        , "from"  .= hFrom h
        , "to"    .= hTo h
        ]

instance FromJSON HorizonResp where
    parseJSON = withObject "HorizonResp" $ \v ->
        fmap HorizonResp (Horizon <$> v .: "key" <*> v .: "label"
                                  <*> v .: "from" <*> v .: "to")

-- -----------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------

parseDay :: String -> Maybe Day
parseDay = parseTimeM True defaultTimeLocale "%Y-%m-%d"

parseTime :: String -> Maybe TimeOfDay
parseTime = parseTimeM True defaultTimeLocale "%H:%M"
