{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Export.JSON
    ( ExportData(..)
    , ExportSkill(..)
    , ExportStation(..)
    , ExportWorker(..)
    , ExportAssignment(..)
    , ExportAbsenceType(..)
    , encodeExport
    , decodeExport
    , gatherExport
    , applyImport
    ) where

import Data.Aeson
    ( ToJSON(..), FromJSON(..), (.=), (.:), (.:?)
    , object, withObject, decode
    )
import Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Time (Day, DayOfWeek(..), TimeOfDay(..), formatTime, defaultTimeLocale, parseTimeM)
import GHC.Generics (Generic)

import Domain.Types
import Domain.Skill (Skill(..), SkillContext(..))
import Domain.Worker (WorkerContext(..))
import Domain.Absence (AbsenceContext(..), AbsenceType(..))
import Auth.Types (User(..), Username(..), Role(..))
import Service.Auth (register)
import Repo.Types (Repository(..))

-- -----------------------------------------------------------------
-- Export data types
-- -----------------------------------------------------------------

data ExportData = ExportData
    { expSkills           :: [ExportSkill]
    , expSkillImplications :: [(Int, Int)]
    , expStations         :: [ExportStation]
    , expWorkers          :: [ExportWorker]
    , expAbsenceTypes     :: [ExportAbsenceType]
    , expSchedules        :: Map.Map String [ExportAssignment]
    } deriving (Show, Generic)

data ExportSkill = ExportSkill
    { esId          :: Int
    , esName        :: String
    , esDescription :: String
    } deriving (Show, Generic)

data ExportStation = ExportStation
    { estId             :: Int
    , estName           :: String
    , estRequiredSkills :: [Int]
    , estStartHour      :: Maybe Int
    , estEndHour        :: Maybe Int
    } deriving (Show, Generic)

data ExportWorker = ExportWorker
    { ewId              :: Int
    , ewUsername        :: String
    , ewRole            :: String
    , ewSkills          :: [Int]
    , ewMaxWeeklyHours  :: Maybe Int
    , ewOvertimeOptIn   :: Bool
    , ewStationPrefs    :: [Int]
    , ewPrefersVariety  :: Bool
    , ewShiftPrefs      :: [String]
    } deriving (Show, Generic)

data ExportAssignment = ExportAssignment
    { eaWorker   :: Int
    , eaStation  :: Int
    , eaDate     :: String
    , eaStart    :: String
    , eaDuration :: Int
    } deriving (Show, Generic)

data ExportAbsenceType = ExportAbsenceType
    { eatId          :: Int
    , eatName        :: String
    , eatYearlyLimit :: Bool
    } deriving (Show, Generic)

-- -----------------------------------------------------------------
-- JSON instances
-- -----------------------------------------------------------------

instance ToJSON ExportData where
    toJSON d = object
        [ "skills"            .= expSkills d
        , "skillImplications" .= map (\(a, b) -> object ["from" .= a, "to" .= b])
                                     (expSkillImplications d)
        , "stations"          .= expStations d
        , "workers"           .= expWorkers d
        , "absenceTypes"      .= expAbsenceTypes d
        , "schedules"         .= expSchedules d
        ]

instance FromJSON ExportData where
    parseJSON = withObject "ExportData" $ \v -> do
        sk   <- v .:? "skills"           >>= pure . maybe [] id
        imps <- v .:? "skillImplications" >>= maybe (pure []) (mapM parseImp)
        st   <- v .:? "stations"         >>= pure . maybe [] id
        wk   <- v .:? "workers"          >>= pure . maybe [] id
        at   <- v .:? "absenceTypes"     >>= pure . maybe [] id
        sch  <- v .:? "schedules"        >>= pure . maybe Map.empty id
        pure $ ExportData sk imps st wk at sch
      where
        parseImp = withObject "implication" $ \v ->
            (,) <$> v .: "from" <*> v .: "to"

instance ToJSON ExportSkill where
    toJSON s = object
        [ "id"          .= esId s
        , "name"        .= esName s
        , "description" .= esDescription s
        ]

instance FromJSON ExportSkill where
    parseJSON = withObject "ExportSkill" $ \v ->
        ExportSkill <$> v .: "id" <*> v .: "name"
                    <*> (v .:? "description" >>= pure . maybe "" id)

instance ToJSON ExportStation where
    toJSON s = object $
        [ "id"             .= estId s
        , "name"           .= estName s
        , "requiredSkills" .= estRequiredSkills s
        ]
        ++ maybe [] (\h -> ["startHour" .= h]) (estStartHour s)
        ++ maybe [] (\h -> ["endHour" .= h]) (estEndHour s)

instance FromJSON ExportStation where
    parseJSON = withObject "ExportStation" $ \v ->
        ExportStation <$> v .: "id" <*> v .: "name"
                      <*> (v .:? "requiredSkills" >>= pure . maybe [] id)
                      <*> v .:? "startHour"
                      <*> v .:? "endHour"

instance ToJSON ExportWorker where
    toJSON w = object
        [ "id"              .= ewId w
        , "username"        .= ewUsername w
        , "role"            .= ewRole w
        , "skills"          .= ewSkills w
        , "maxWeeklyHours"  .= ewMaxWeeklyHours w
        , "overtimeOptIn"   .= ewOvertimeOptIn w
        , "stationPrefs"    .= ewStationPrefs w
        , "prefersVariety"  .= ewPrefersVariety w
        , "shiftPrefs"      .= ewShiftPrefs w
        ]

instance FromJSON ExportWorker where
    parseJSON = withObject "ExportWorker" $ \v ->
        ExportWorker <$> v .: "id" <*> v .: "username"
                     <*> (v .:? "role" >>= pure . maybe "normal" id)
                     <*> (v .:? "skills" >>= pure . maybe [] id)
                     <*> v .:? "maxWeeklyHours"
                     <*> (v .:? "overtimeOptIn" >>= pure . maybe False id)
                     <*> (v .:? "stationPrefs" >>= pure . maybe [] id)
                     <*> (v .:? "prefersVariety" >>= pure . maybe False id)
                     <*> (v .:? "shiftPrefs" >>= pure . maybe [] id)

instance ToJSON ExportAssignment where
    toJSON a = object
        [ "worker"   .= eaWorker a
        , "station"  .= eaStation a
        , "date"     .= eaDate a
        , "start"    .= eaStart a
        , "duration" .= eaDuration a
        ]

instance FromJSON ExportAssignment where
    parseJSON = withObject "ExportAssignment" $ \v ->
        ExportAssignment <$> v .: "worker" <*> v .: "station"
                         <*> v .: "date" <*> v .: "start"
                         <*> (v .:? "duration" >>= pure . maybe 3600 id)

instance ToJSON ExportAbsenceType where
    toJSON a = object
        [ "id"          .= eatId a
        , "name"        .= eatName a
        , "yearlyLimit" .= eatYearlyLimit a
        ]

instance FromJSON ExportAbsenceType where
    parseJSON = withObject "ExportAbsenceType" $ \v ->
        ExportAbsenceType <$> v .: "id" <*> v .: "name"
                          <*> (v .:? "yearlyLimit" >>= pure . maybe False id)

-- -----------------------------------------------------------------
-- Encode / decode
-- -----------------------------------------------------------------

encodeExport :: ExportData -> BL.ByteString
encodeExport = encodePretty

decodeExport :: BL.ByteString -> Maybe ExportData
decodeExport = decode

-- -----------------------------------------------------------------
-- Gather export data from repository
-- -----------------------------------------------------------------

gatherExport :: Repository -> Maybe String -> IO ExportData
gatherExport repo mSchedName = do
    -- Skills
    skillList <- repoListSkills repo
    let expSk = [ ExportSkill sid (T.unpack nm) (T.unpack desc)
                 | (SkillId sid, Skill nm desc) <- skillList ]

    -- Skill context (for implications, station requirements, worker skills)
    skillCtx <- repoLoadSkillCtx repo

    let expImps = [ (a, b)
                  | (SkillId a, bs) <- Map.toList (scSkillImplies skillCtx)
                  , SkillId b <- Set.toList bs ]

    -- Stations
    stationList <- repoListStations repo
    let expSt = [ let dayMap = Map.findWithDefault Map.empty (StationId sid) (scStationHours skillCtx)
                      openHours = concatMap snd (Map.toList dayMap)
                      mStart = if null openHours then Nothing else Just (minimum openHours)
                      mEnd   = if null openHours then Nothing else Just (maximum openHours + 1)
                  in ExportStation sid nm
                    (map (\(SkillId s) -> s) $ Set.toList $
                        Map.findWithDefault Set.empty (StationId sid) (scStationRequires skillCtx))
                    mStart mEnd
                | (StationId sid, nm) <- stationList ]

    -- Workers / Users
    users <- repoListUsers repo
    workerCtx <- repoLoadWorkerCtx repo

    let expWk = [ ExportWorker wid uname (roleStr (userRole u))
                    (map (\(SkillId s) -> s) $ Set.toList $
                        Map.findWithDefault Set.empty (WorkerId wid) (scWorkerSkills skillCtx))
                    (fmap (\dt -> round (toRational dt / 3600)) $
                        Map.lookup (WorkerId wid) (wcMaxPeriodHours workerCtx))
                    (Set.member (WorkerId wid) (wcOvertimeOptIn workerCtx))
                    (map (\(StationId s) -> s) $
                        Map.findWithDefault [] (WorkerId wid) (wcStationPrefs workerCtx))
                    (Set.member (WorkerId wid) (wcPrefersVariety workerCtx))
                    (Map.findWithDefault [] (WorkerId wid) (wcShiftPrefs workerCtx))
                | u <- users
                , let WorkerId wid = userWorkerId u
                      Username uname = userName u
                ]

    -- Absence types
    absCtx <- repoLoadAbsenceCtx repo
    let expAt = [ ExportAbsenceType tid (atName at) (atYearlyLimit at)
                | (AbsenceTypeId tid, at) <- Map.toList (acTypes absCtx) ]

    -- Schedules
    schedNames <- case mSchedName of
        Just n  -> pure [n]
        Nothing -> repoListSchedules repo

    scheds <- fmap Map.fromList $ mapM (\nm -> do
        ms <- repoLoadSchedule repo nm
        let assignments = case ms of
                Nothing -> []
                Just (Schedule as) ->
                    [ ExportAssignment w s
                        (formatTime defaultTimeLocale "%Y-%m-%d" (slotDate sl))
                        (formatTime defaultTimeLocale "%H:%M" (slotStart sl))
                        (round (toRational (slotDuration sl)))
                    | Assignment (WorkerId w) (StationId s) sl <- Set.toList as ]
        pure (nm, assignments)
        ) schedNames

    pure $ ExportData expSk expImps expSt expWk expAt scheds

roleStr :: Role -> String
roleStr Admin  = "admin"
roleStr Normal = "normal"

-- -----------------------------------------------------------------
-- Apply import data to repository
-- -----------------------------------------------------------------

applyImport :: Repository -> ExportData -> IO [String]
applyImport repo dat = do
    -- Load existing users to validate worker references
    users <- repoListUsers repo
    let existingWorkers = Set.fromList [userWorkerId u | u <- users]
    msgs <- sequence $ concat
        [ map importSkill (expSkills dat)
        , map importStation (expStations dat)
        , map importImplication (expSkillImplications dat)
        , map (importWorker existingWorkers) (expWorkers dat)
        , map importAbsenceType (expAbsenceTypes dat)
        , map (uncurry importSchedule) (Map.toList (expSchedules dat))
        ]
    pure msgs
  where
    importSkill (ExportSkill sid nm desc) = do
        _ <- repoCreateSkill repo (SkillId sid) nm desc
        pure ("Imported skill " ++ show sid ++ ": " ++ nm)

    importStation (ExportStation sid nm reqSkills mSh mEh) = do
        repoCreateStation repo (StationId sid) nm
        -- Set required skills and optional hours
        skillCtx <- repoLoadSkillCtx repo
        let hours = case (mSh, mEh) of
                (Just sh, Just eh) ->
                    let allDays = [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]
                        dayMap = Map.fromList [(dow, [sh..eh-1]) | dow <- allDays]
                    in Map.insert (StationId sid) dayMap (scStationHours skillCtx)
                _                  -> scStationHours skillCtx
            ctx' = skillCtx
                { scStationRequires = Map.insert (StationId sid)
                    (Set.fromList [SkillId s | s <- reqSkills])
                    (scStationRequires skillCtx)
                , scAllStations = Set.insert (StationId sid) (scAllStations skillCtx)
                , scStationHours = hours
                }
        repoSaveSkillCtx repo ctx'
        pure ("Imported station " ++ show sid ++ ": " ++ nm)

    importImplication (a, b) = do
        skillCtx <- repoLoadSkillCtx repo
        let existing = Map.findWithDefault Set.empty (SkillId a) (scSkillImplies skillCtx)
            ctx' = skillCtx
                { scSkillImplies = Map.insert (SkillId a)
                    (Set.insert (SkillId b) existing) (scSkillImplies skillCtx)
                }
        repoSaveSkillCtx repo ctx'
        pure ("Imported implication: skill " ++ show a ++ " -> skill " ++ show b)

    importWorker existingWorkers ew = do
        let wid = WorkerId (ewId ew)
            role = if ewRole ew == "admin" then Admin else Normal
        createMsg <- if Set.member wid existingWorkers
            then pure Nothing
            else do
                result <- register repo (ewUsername ew) "changeme" role wid
                pure $ Just $ case result of
                    Right _  -> "Created user '" ++ ewUsername ew
                                ++ "' (worker " ++ show (ewId ew)
                                ++ ") with default password 'changeme'"
                    Left err -> "WARNING: could not create user '" ++ ewUsername ew
                                ++ "': " ++ show err
        do  -- Update worker attributes regardless
            skillCtx <- repoLoadSkillCtx repo
            let ctx' = skillCtx
                    { scWorkerSkills = Map.insert wid
                        (Set.fromList [SkillId s | s <- ewSkills ew])
                        (scWorkerSkills skillCtx)
                    }
            repoSaveSkillCtx repo ctx'

            -- Set worker context attributes
            workerCtx <- repoLoadWorkerCtx repo
            let wctx' = workerCtx
                    { wcMaxPeriodHours = case ewMaxWeeklyHours ew of
                        Nothing -> Map.delete wid (wcMaxPeriodHours workerCtx)
                        Just h  -> Map.insert wid (fromIntegral h * 3600)
                                   (wcMaxPeriodHours workerCtx)
                    , wcOvertimeOptIn = if ewOvertimeOptIn ew
                        then Set.insert wid (wcOvertimeOptIn workerCtx)
                        else Set.delete wid (wcOvertimeOptIn workerCtx)
                    , wcStationPrefs = if null (ewStationPrefs ew)
                        then Map.delete wid (wcStationPrefs workerCtx)
                        else Map.insert wid [StationId s | s <- ewStationPrefs ew]
                             (wcStationPrefs workerCtx)
                    , wcPrefersVariety = if ewPrefersVariety ew
                        then Set.insert wid (wcPrefersVariety workerCtx)
                        else Set.delete wid (wcPrefersVariety workerCtx)
                    , wcShiftPrefs = if null (ewShiftPrefs ew)
                        then Map.delete wid (wcShiftPrefs workerCtx)
                        else Map.insert wid (ewShiftPrefs ew) (wcShiftPrefs workerCtx)
                    , wcWeekendOnly = wcWeekendOnly workerCtx  -- preserved from existing context
                    }
            repoSaveWorkerCtx repo wctx'
            let attrMsg = "Imported worker " ++ show (ewId ew) ++ " (" ++ ewUsername ew ++ ") attributes"
            pure $ case createMsg of
                Nothing  -> attrMsg
                Just msg -> msg ++ "\n" ++ attrMsg

    importAbsenceType (ExportAbsenceType tid nm yearly) = do
        absCtx <- repoLoadAbsenceCtx repo
        let ctx' = absCtx
                { acTypes = Map.insert (AbsenceTypeId tid)
                    (AbsenceType nm yearly) (acTypes absCtx)
                }
        repoSaveAbsenceCtx repo ctx'
        pure ("Imported absence type " ++ show tid ++ ": " ++ nm)

    importSchedule nm assignments = do
        let parsed = [ Assignment (WorkerId (eaWorker a)) (StationId (eaStation a))
                        (Slot day start (fromIntegral (eaDuration a)))
                     | a <- assignments
                     , Just day <- [parseDay' (eaDate a)]
                     , Just start <- [parseTime' (eaStart a)]
                     ]
        repoSaveSchedule repo nm (Schedule (Set.fromList parsed))
        pure ("Imported schedule '" ++ nm ++ "' with "
             ++ show (length parsed) ++ " assignments")

parseDay' :: String -> Maybe Day
parseDay' = parseTimeM True defaultTimeLocale "%Y-%m-%d"

parseTime' :: String -> Maybe TimeOfDay
parseTime' = parseTimeM True defaultTimeLocale "%H:%M"
