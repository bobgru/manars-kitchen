{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server.Json
    ( -- * Request types
      CreateDraftReq(..)
    , GenerateDraftReq(..)
    , CommitDraftReq(..)
    , RequestAbsenceReq(..)
      -- * Response types
    , DraftCreatedResp(..)
    , AbsenceCreatedResp(..)
    ) where

import Data.Aeson
    ( ToJSON(..), FromJSON(..), (.=), (.:)
    , object, withObject, withText
    )
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (unpack)
import Data.Time
    ( Day, TimeOfDay(..)
    , formatTime, defaultTimeLocale, parseTimeM
    )

import Domain.Types
import Domain.Skill (Skill(..))
import Domain.Shift (ShiftDef(..))
import Domain.Scheduler (ScheduleResult(..), Unfilled(..), UnfilledKind(..))
import Domain.Absence (AbsenceRequest(..), AbsenceStatus(..))
import Repo.Types (DraftInfo(..), CalendarCommit(..))

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
        pure (CalendarCommit i ca df dt n)

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

data GenerateDraftReq = GenerateDraftReq
    { gdrWorkerIds :: ![Int]
    } deriving (Show)

instance ToJSON GenerateDraftReq where
    toJSON r = object ["workerIds" .= gdrWorkerIds r]

instance FromJSON GenerateDraftReq where
    parseJSON = withObject "GenerateDraftReq" $ \v ->
        GenerateDraftReq <$> v .: "workerIds"

data CommitDraftReq = CommitDraftReq
    { cmrNote :: !String
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

data AbsenceCreatedResp = AbsenceCreatedResp
    { acrId :: !Int
    } deriving (Show, Eq)

instance ToJSON AbsenceCreatedResp where
    toJSON r = object ["id" .= acrId r]

instance FromJSON AbsenceCreatedResp where
    parseJSON = withObject "AbsenceCreatedResp" $ \v ->
        AbsenceCreatedResp <$> v .: "id"

-- -----------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------

parseDay :: String -> Maybe Day
parseDay = parseTimeM True defaultTimeLocale "%Y-%m-%d"

parseTime :: String -> Maybe TimeOfDay
parseTime = parseTimeM True defaultTimeLocale "%H:%M"
