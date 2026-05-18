{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
module Repo.SQLite
    ( mkSQLiteRepo
    ) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import Data.Time (Day, UTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import Database.SQLite.Simple
import Numeric (showHex)
import System.Random (randomRIO)

import Audit.CommandMeta (CommandMeta(..))
import Auth.Types (UserId(..), Username(..), Role(..), User(..))
import Data.Time (DayOfWeek(..))
import Domain.Absence
    ( AbsenceType(..)
    , AbsenceRequest(..), AbsenceContext(..)
    )
import Domain.Hint (Hint, encodeHints, decodeHints)
import Domain.PayPeriod (PayPeriodConfig(..), parsePayPeriodType, showPayPeriodType)
import Domain.Pin (PinnedAssignment(..), PinSpec(..))
import Domain.SchedulerConfig (SchedulerConfig, configToMap, configFromMap)
import Domain.Shift (ShiftDef(..))
import Domain.Skill (Skill(..), SkillContext(..))
import Domain.Types
    ( WorkerId(..), StationId(..), Station(..), SkillId(..)
    , AbsenceId(..), AbsenceTypeId(..)
    , WorkerStatus(..), workerStatusToText, textToWorkerStatus
    , Slot(..), Assignment(..), Schedule(..)
    )
import Domain.Worker (WorkerContext(..), OvertimeModel(..), PayPeriodTracking(..))
import Repo.Schema (initSchema)
import Repo.Serialize
import Repo.Types (Repository(..), CalendarCommit(..), DraftInfo(..), AuditEntry(..), SessionId(..), HintSessionRecord(..), WorkerSummary(..))
import Utils (shellQuote)

-- | Create a Repository backed by a SQLite database at the given path.
-- Creates the schema if it doesn't exist.
mkSQLiteRepo :: FilePath -> IO (Connection, Repository)
mkSQLiteRepo path = do
    conn <- open path
    execute_ conn "PRAGMA journal_mode=WAL"
    execute_ conn "PRAGMA foreign_keys=ON"
    initSchema conn
    return (conn, Repository
        { repoCreateUser     = sqlCreateUser conn
        , repoGetUser        = sqlGetUser conn
        , repoGetUserByName  = sqlGetUserByName conn
        , repoUpdatePassword = sqlUpdatePassword conn
        , repoListUsers      = sqlListUsers conn
        , repoDeleteUser     = sqlDeleteUser conn
        , repoRenameUser     = sqlRenameUser conn
        , repoSetWorkerStatus = sqlSetWorkerStatus conn
        , repoLoadWorkerIdsByStatus = sqlLoadWorkerIdsByStatus conn
        , repoListWorkerSummaries = sqlListWorkerSummaries conn
        , repoCascadeWorkerConfig = sqlCascadeWorkerConfig conn
        , repoCascadeWorkerSchedule = sqlCascadeWorkerSchedule conn
        , repoDeactivateClearings = sqlDeactivateClearings conn
        , repoForceDeleteUser = sqlForceDeleteUser conn
        , repoCreateSkill    = sqlCreateSkill conn
        , repoDeleteSkill    = sqlDeleteSkill conn
        , repoListSkills     = sqlListSkills conn
        , repoRenameSkill    = sqlRenameSkill conn
        , repoListSkillImplications = sqlListSkillImplications conn
        , repoRemoveSkillImplication = sqlRemoveSkillImplication conn
        , repoCreateStation  = sqlCreateStation conn
        , repoDeleteStation  = sqlDeleteStation conn
        , repoListStations   = sqlListStations conn
        , repoRenameStation  = sqlRenameStation conn
        , repoSaveSkillCtx   = sqlSaveSkillCtx conn
        , repoLoadSkillCtx   = sqlLoadSkillCtx conn
        , repoSaveWorkerCtx  = sqlSaveWorkerCtx conn
        , repoLoadWorkerCtx  = sqlLoadWorkerCtx conn
        , repoLoadEmployment = sqlLoadEmployment conn
        , repoSaveEmployment = sqlSaveEmployment conn
        , repoSaveAbsenceCtx = sqlSaveAbsenceCtx conn
        , repoLoadAbsenceCtx = sqlLoadAbsenceCtx conn
        , repoSaveShift      = sqlSaveShift conn
        , repoDeleteShift    = sqlDeleteShift conn
        , repoLoadShifts     = sqlLoadShifts conn
        , repoSaveSchedule   = sqlSaveSchedule conn
        , repoLoadSchedule   = sqlLoadSchedule conn
        , repoListSchedules  = sqlListSchedules conn
        , repoDeleteSchedule = sqlDeleteSchedule conn
        , repoSaveSchedulerConfig = sqlSaveSchedulerConfig conn
        , repoLoadSchedulerConfig = sqlLoadSchedulerConfig conn
        , repoLoadPayPeriodConfig = sqlLoadPayPeriodConfig conn
        , repoSavePayPeriodConfig = sqlSavePayPeriodConfig conn
        , repoSavePins       = sqlSavePins conn
        , repoLoadPins       = sqlLoadPins conn
        , repoLogCommandWithMeta = sqlLogCommandWithMeta conn
        , repoGetAuditLog    = sqlGetAuditLog conn
        , repoWipeAll        = sqlWipeAll conn
        , repoSaveCalendar   = sqlSaveCalendar conn
        , repoLoadCalendar   = sqlLoadCalendar conn
        , repoSaveCommit     = sqlSaveCommit conn
        , repoListCommits    = sqlListCommits conn
        , repoLoadCommitAssignments = sqlLoadCommitAssignments conn
        , repoCreateDraft    = sqlCreateDraft conn
        , repoDeleteDraft    = sqlDeleteDraft conn
        , repoListDrafts     = sqlListDrafts conn
        , repoGetDraft       = sqlGetDraft conn
        , repoCheckDraftOverlap = sqlCheckDraftOverlap conn
        , repoSaveDraftAssignments = sqlSaveDraftAssignments conn
        , repoLoadDraftAssignments = sqlLoadDraftAssignments conn
        , repoCalendarCommitsAfter = sqlCalendarCommitsAfter conn
        , repoUpdateDraftValidatedAt = sqlUpdateDraftValidatedAt conn
        , repoSavepoint      = sqlSavepoint conn
        , repoRelease        = sqlRelease conn
        , repoRollbackTo     = sqlRollbackTo conn
        , repoCreateSession    = sqlCreateSession conn
        , repoGetActiveSession = sqlGetActiveSession conn
        , repoTouchSession     = sqlTouchSession conn
        , repoCloseSession     = sqlCloseSession conn
        , repoGetSessionByToken = sqlGetSessionByToken conn
        , repoGetSessionOwner = sqlGetSessionOwner conn
        , repoGetIdleTimeoutMinutes = sqlGetIdleTimeoutMinutes conn
        , repoSaveHintSession   = sqlSaveHintSession conn
        , repoLoadHintSession   = sqlLoadHintSession conn
        , repoDeleteHintSession = sqlDeleteHintSession conn
        , repoAuditSince        = sqlAuditSince conn
        })

-- =====================================================================
-- Users
-- =====================================================================

sqlCreateUser :: Connection -> Text -> Text -> Role -> Bool -> IO UserId
sqlCreateUser conn name passHash role noWorker = do
    let status = if noWorker then WSNone else WSActive
    execute conn
        "INSERT INTO users (username, password_hash, role, worker_status, deactivated_at) \
        \VALUES (?, ?, ?, ?, NULL)"
        (name, passHash, roleToText role, workerStatusToText status)
    UserId . fromIntegral <$> lastInsertRowId conn

sqlGetUser :: Connection -> UserId -> IO (Maybe User)
sqlGetUser conn (UserId uid) = do
    rows <- query conn
        "SELECT id, username, password_hash, role, worker_status, deactivated_at FROM users WHERE id = ?"
        (Only uid)
    return $ case rows of
        [(i, n, h, r, ws, da)] -> Just (toUser i n h r ws da)
        _                       -> Nothing

sqlGetUserByName :: Connection -> Text -> IO (Maybe User)
sqlGetUserByName conn name = do
    rows <- query conn
        "SELECT id, username, password_hash, role, worker_status, deactivated_at FROM users WHERE username = ?"
        (Only name)
    return $ case rows of
        [(i, n, h, r, ws, da)] -> Just (toUser i n h r ws da)
        _                       -> Nothing

sqlUpdatePassword :: Connection -> UserId -> Text -> IO ()
sqlUpdatePassword conn (UserId uid) passHash =
    execute conn "UPDATE users SET password_hash = ? WHERE id = ?" (passHash, uid)

sqlListUsers :: Connection -> IO [User]
sqlListUsers conn = do
    rows <- query_ conn "SELECT id, username, password_hash, role, worker_status, deactivated_at FROM users"
    return [toUser i n h r ws da | (i, n, h, r, ws, da) <- rows]

sqlDeleteUser :: Connection -> UserId -> IO ()
sqlDeleteUser conn (UserId uid) =
    execute conn "DELETE FROM users WHERE id = ?" (Only uid)

sqlRenameUser :: Connection -> UserId -> Text -> IO ()
sqlRenameUser conn (UserId uid) newName =
    execute conn "UPDATE users SET username = ? WHERE id = ?" (newName, uid)

sqlSetWorkerStatus :: Connection -> UserId -> WorkerStatus -> Maybe Day -> IO ()
sqlSetWorkerStatus conn (UserId uid) status mDay =
    execute conn
        "UPDATE users SET worker_status = ?, deactivated_at = ? WHERE id = ?"
        (workerStatusToText status, fmap dayToText mDay, uid)

sqlLoadWorkerIdsByStatus :: Connection -> WorkerStatus -> IO [WorkerId]
sqlLoadWorkerIdsByStatus conn status = do
    rows <- query conn
        "SELECT id FROM users WHERE worker_status = ?"
        (Only (workerStatusToText status))
        :: IO [Only Int]
    return [WorkerId i | Only i <- rows]

-- | List slim worker summaries. Excludes users with @worker_status='none'@.
-- Filters by status when @Just s@ is provided.
sqlListWorkerSummaries :: Connection -> Maybe WorkerStatus -> IO [WorkerSummary]
sqlListWorkerSummaries conn mStatus = do
    let baseQ = "SELECT u.username, u.role, u.worker_status, \
                \COALESCE(we.is_temp, 0), \
                \(CASE WHEN wo.worker_id IS NOT NULL THEN 1 ELSE 0 END), \
                \COALESCE(ws.level, 1) \
                \FROM users u \
                \LEFT JOIN worker_employment we ON we.worker_id = u.id \
                \LEFT JOIN worker_weekend_only wo ON wo.worker_id = u.id \
                \LEFT JOIN worker_seniority ws ON ws.worker_id = u.id "
    rows <- case mStatus of
        Just s -> query conn
            (fromString (baseQ ++ "WHERE u.worker_status = ? ORDER BY u.username"))
            (Only (workerStatusToText s))
            :: IO [(Text, Text, Text, Int, Int, Int)]
        Nothing -> query_ conn
            (fromString (baseQ ++ "WHERE u.worker_status IN ('active', 'inactive') ORDER BY u.username"))
            :: IO [(Text, Text, Text, Int, Int, Int)]
    pure
        [ WorkerSummary
            { wsName        = n
            , wsRole        = role
            , wsStatus      = case textToWorkerStatus ws of
                                Just s  -> s
                                Nothing -> WSNone
            , wsIsTemp      = isTemp /= 0
            , wsWeekendOnly = weekend /= 0
            , wsSeniority   = sen
            }
        | (n, role, ws, isTemp, weekend, sen) <- rows
        ]

sqlCascadeWorkerConfig :: Connection -> WorkerId -> IO ()
sqlCascadeWorkerConfig conn (WorkerId wid) = withTransaction conn $ do
    execute conn "DELETE FROM worker_skills WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_hours WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_overtime_optin WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_station_prefs WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_prefers_variety WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_shift_prefs WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_weekend_only WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_seniority WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_avoid_pairing WHERE worker_id = ? OR other_id = ?" (wid, wid)
    execute conn "DELETE FROM worker_prefer_pairing WHERE worker_id = ? OR other_id = ?" (wid, wid)
    execute conn "DELETE FROM worker_cross_training WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM worker_employment WHERE worker_id = ?" (Only wid)

sqlCascadeWorkerSchedule :: Connection -> WorkerId -> IO ()
sqlCascadeWorkerSchedule conn (WorkerId wid) = withTransaction conn $ do
    execute conn "DELETE FROM pinned_assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM calendar_assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM draft_assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM absence_requests WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM yearly_allowances WHERE worker_id = ?" (Only wid)

sqlDeactivateClearings :: Connection -> WorkerId -> Day -> IO (Int, Int, Int)
sqlDeactivateClearings conn (WorkerId wid) today = withTransaction conn $ do
    pinRows  <- query conn "SELECT COUNT(*) FROM pinned_assignments WHERE worker_id = ?"
                    (Only wid) :: IO [Only Int]
    drftRows <- query conn "SELECT COUNT(*) FROM draft_assignments WHERE worker_id = ?"
                    (Only wid) :: IO [Only Int]
    calRows  <- query conn
                    "SELECT COUNT(*) FROM calendar_assignments WHERE worker_id = ? AND slot_date >= ?"
                    (wid, dayToText today) :: IO [Only Int]
    let pinCount = case pinRows of  { [Only n] -> n; _ -> 0 }
        drftCount = case drftRows of { [Only n] -> n; _ -> 0 }
        calCount = case calRows of   { [Only n] -> n; _ -> 0 }
    execute conn "DELETE FROM pinned_assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM draft_assignments WHERE worker_id = ?" (Only wid)
    execute conn "DELETE FROM calendar_assignments WHERE worker_id = ? AND slot_date >= ?"
        (wid, dayToText today)
    return (pinCount, drftCount, calCount)

sqlForceDeleteUser :: Connection -> UserId -> IO ()
sqlForceDeleteUser conn uid@(UserId i) = withTransaction conn $ do
    sqlCascadeWorkerSchedule conn (WorkerId i)
    sqlCascadeWorkerConfig conn (WorkerId i)
    execute conn "DELETE FROM users WHERE id = ?" (Only i)
    -- silence unused binding warning
    _ <- pure uid
    return ()

toUser :: Int -> Text -> Text -> Text -> Text -> Maybe Text -> User
toUser i n h r ws da = User
    { userId            = UserId i
    , userName          = Username n
    , userPassHash      = h
    , userRole          = textToRole r
    , userWorkerStatus  = case textToWorkerStatus ws of
                            Just s  -> s
                            Nothing -> WSNone
    , userDeactivatedAt = fmap textToDay da
    }

-- =====================================================================
-- Skills (entity CRUD — preserves name/description)
-- =====================================================================

sqlCreateSkill :: Connection -> Text -> Text -> IO (Either String ())
sqlCreateSkill conn name desc = do
    existing <- query conn "SELECT name FROM skills WHERE name = ?" (Only name) :: IO [[Text]]
    case existing of
        [_]:_ -> return $ Left $
            "Skill " ++ T.unpack name ++ " already exists. Use 'skill rename " ++ shellQuote (T.unpack name) ++ " <new-name>' to rename."
        _ -> do
            execute conn
                "INSERT INTO skills (name, description) VALUES (?, ?)"
                (name, desc)
            return $ Right ()

sqlDeleteSkill :: Connection -> SkillId -> IO ()
sqlDeleteSkill conn (SkillId sid) = do
    execute conn "DELETE FROM skill_implications WHERE skill_id = ? OR implies_skill_id = ?" (sid, sid)
    execute conn "DELETE FROM worker_skills WHERE skill_id = ?" (Only sid)
    execute conn "DELETE FROM station_required_skills WHERE skill_id = ?" (Only sid)
    execute conn "DELETE FROM worker_cross_training WHERE skill_id = ?" (Only sid)
    execute conn "DELETE FROM skills WHERE id = ?" (Only sid)

sqlListSkills :: Connection -> IO [(SkillId, Skill)]
sqlListSkills conn = do
    rows <- query_ conn "SELECT id, name, description FROM skills ORDER BY id"
        :: IO [(Int, Text, Text)]
    return [(SkillId sid, Skill name desc) | (sid, name, desc) <- rows]

sqlRenameSkill :: Connection -> SkillId -> Text -> IO ()
sqlRenameSkill conn (SkillId sid) newName =
    execute conn "UPDATE skills SET name = ? WHERE id = ?" (newName, sid)

sqlListSkillImplications :: Connection -> IO [(SkillId, SkillId)]
sqlListSkillImplications conn = do
    rows <- query_ conn "SELECT skill_id, implies_skill_id FROM skill_implications"
        :: IO [(Int, Int)]
    return [(SkillId s, SkillId i) | (s, i) <- rows]

sqlRemoveSkillImplication :: Connection -> SkillId -> SkillId -> IO ()
sqlRemoveSkillImplication conn (SkillId s) (SkillId i) =
    execute conn
        "DELETE FROM skill_implications WHERE skill_id = ? AND implies_skill_id = ?"
        (s, i)

-- =====================================================================
-- Stations (entity CRUD)
-- =====================================================================

sqlCreateStation :: Connection -> Text -> Int -> Int -> IO StationId
sqlCreateStation conn name minStaff maxStaff = do
    execute conn
        "INSERT INTO stations (name, min_staff, max_staff) VALUES (?, ?, ?)"
        (name, minStaff, maxStaff)
    rowId <- lastInsertRowId conn
    return (StationId (fromIntegral rowId))

sqlDeleteStation :: Connection -> StationId -> IO ()
sqlDeleteStation conn (StationId sid) = do
    execute conn "DELETE FROM station_required_skills WHERE station_id = ?" (Only sid)
    execute conn "DELETE FROM stations WHERE id = ?" (Only sid)

sqlListStations :: Connection -> IO [(StationId, Station)]
sqlListStations conn = do
    rows <- query_ conn "SELECT id, name, min_staff, max_staff FROM stations ORDER BY id"
        :: IO [(Int, Text, Int, Int)]
    return [(StationId sid, Station name minS maxS) | (sid, name, minS, maxS) <- rows]

sqlRenameStation :: Connection -> StationId -> Text -> IO ()
sqlRenameStation conn (StationId sid) newName =
    execute conn "UPDATE stations SET name = ? WHERE id = ?" (newName, sid)

-- =====================================================================
-- Skill context (relational data — does NOT touch skills/stations tables)
-- =====================================================================

sqlSaveSkillCtx :: Connection -> SkillContext -> IO ()
sqlSaveSkillCtx conn ctx = withTransaction conn $ do
    -- Clear relational data only (not entity metadata)
    execute_ conn "DELETE FROM skill_implications"
    execute_ conn "DELETE FROM station_required_skills"
    execute_ conn "DELETE FROM worker_skills"
    execute_ conn "DELETE FROM station_open_hours"
    execute_ conn "DELETE FROM station_multi_hours"

    -- Stations are created via repoCreateStation (auto-increment);
    -- scAllStations tracks which ones exist for the skill context.

    -- Skill implications
    mapM_ (\(SkillId sid, implies) ->
        mapM_ (\(SkillId imp) ->
            execute conn "INSERT INTO skill_implications (skill_id, implies_skill_id) VALUES (?, ?)"
                (sid, imp)
            ) (Set.toList implies)
        ) (Map.toList (scSkillImplies ctx))

    -- Worker skills
    mapM_ (\(WorkerId wid, skills) ->
        mapM_ (\(SkillId sid) ->
            execute conn "INSERT INTO worker_skills (worker_id, skill_id) VALUES (?, ?)"
                (wid, sid)
            ) (Set.toList skills)
        ) (Map.toList (scWorkerSkills ctx))

    -- Station required skills
    mapM_ (\(StationId sid, skills) ->
        mapM_ (\(SkillId skid) ->
            execute conn "INSERT INTO station_required_skills (station_id, skill_id) VALUES (?, ?)"
                (sid, skid)
            ) (Set.toList skills)
        ) (Map.toList (scStationRequires ctx))

    -- Station open hours (per day-of-week)
    -- Use hour=-1 as sentinel for "explicitly closed on this day"
    mapM_ (\(StationId sid, dayHoursMap) ->
        mapM_ (\(dow, hours) ->
            case hours of
                [] -> execute conn
                    "INSERT INTO station_open_hours (station_id, day_of_week, hour) VALUES (?, ?, ?)"
                    (sid, showDow dow, (-1 :: Int))
                _  -> mapM_ (\h ->
                    execute conn
                        "INSERT INTO station_open_hours (station_id, day_of_week, hour) VALUES (?, ?, ?)"
                        (sid, showDow dow, h)
                    ) hours
            ) (Map.toList dayHoursMap)
        ) (Map.toList (scStationHours ctx))

    -- Station multi-station hours (per day-of-week)
    mapM_ (\(StationId sid, dayHoursMap) ->
        mapM_ (\(dow, hours) ->
            mapM_ (\h ->
                execute conn
                    "INSERT INTO station_multi_hours (station_id, day_of_week, hour) VALUES (?, ?, ?)"
                    (sid, showDow dow, h)
                ) hours
            ) (Map.toList dayHoursMap)
        ) (Map.toList (scMultiStationHours ctx))

sqlLoadSkillCtx :: Connection -> IO SkillContext
sqlLoadSkillCtx conn = do
    -- Worker skills
    wsRows <- query_ conn "SELECT worker_id, skill_id FROM worker_skills"
        :: IO [(Int, Int)]
    let workerSkills = Map.fromListWith Set.union
            [(WorkerId w, Set.singleton (SkillId s)) | (w, s) <- wsRows]

    -- Station required skills
    srRows <- query_ conn "SELECT station_id, skill_id FROM station_required_skills"
        :: IO [(Int, Int)]
    let stationReqs = Map.fromListWith Set.union
            [(StationId st, Set.singleton (SkillId sk)) | (st, sk) <- srRows]

    -- Skill implications
    siRows <- query_ conn "SELECT skill_id, implies_skill_id FROM skill_implications"
        :: IO [(Int, Int)]
    let skillImplies = Map.fromListWith Set.union
            [(SkillId s, Set.singleton (SkillId i)) | (s, i) <- siRows]

    -- Stations
    stRows <- query_ conn "SELECT id FROM stations"
        :: IO [Only Int]
    let allStations = Set.fromList [StationId s | Only s <- stRows]

    -- Station open hours (per day-of-week)
    -- hour=-1 is a sentinel for "explicitly closed on this day"
    shRows <- query_ conn "SELECT station_id, day_of_week, hour FROM station_open_hours"
        :: IO [(Int, String, Int)]
    let stationHours = Map.fromListWith (Map.unionWith (++))
            [ (StationId s, Map.singleton (parseDow d) (if h == -1 then [] else [h]))
            | (s, d, h) <- shRows ]

    -- Station multi-station hours
    mhRows <- query_ conn "SELECT station_id, day_of_week, hour FROM station_multi_hours"
        :: IO [(Int, String, Int)]
    let multiStationHours = Map.fromListWith (Map.unionWith (++))
            [ (StationId s, Map.singleton (parseDow d) [h])
            | (s, d, h) <- mhRows ]

    return SkillContext
        { scWorkerSkills    = workerSkills
        , scStationRequires = stationReqs
        , scSkillImplies    = skillImplies
        , scAllStations     = allStations
        , scStationHours    = stationHours
        , scMultiStationHours = multiStationHours
        }

-- =====================================================================
-- Worker context
-- =====================================================================

sqlSaveWorkerCtx :: Connection -> WorkerContext -> IO ()
sqlSaveWorkerCtx conn ctx = withTransaction conn $ do
    execute_ conn "DELETE FROM worker_hours"
    execute_ conn "DELETE FROM worker_overtime_optin"
    execute_ conn "DELETE FROM worker_station_prefs"
    execute_ conn "DELETE FROM worker_prefers_variety"
    execute_ conn "DELETE FROM worker_shift_prefs"
    execute_ conn "DELETE FROM worker_weekend_only"

    -- Max weekly hours
    mapM_ (\(WorkerId wid, dt) ->
        execute conn "INSERT INTO worker_hours (worker_id, max_period_seconds) VALUES (?, ?)"
            (wid, diffTimeToSeconds dt)
        ) (Map.toList (wcMaxPeriodHours ctx))

    -- Overtime opt-in
    mapM_ (\(WorkerId wid) ->
        execute conn "INSERT INTO worker_overtime_optin (worker_id) VALUES (?)"
            (Only wid)
        ) (Set.toList (wcOvertimeOptIn ctx))

    -- Station preferences
    mapM_ (\(WorkerId wid, prefs) ->
        mapM_ (\(rank, StationId sid) ->
            execute conn
                "INSERT INTO worker_station_prefs (worker_id, station_id, rank) VALUES (?, ?, ?)"
                (wid, sid, rank)
            ) (zip [(0::Int)..] prefs)
        ) (Map.toList (wcStationPrefs ctx))

    -- Prefers variety
    mapM_ (\(WorkerId wid) ->
        execute conn "INSERT INTO worker_prefers_variety (worker_id) VALUES (?)"
            (Only wid)
        ) (Set.toList (wcPrefersVariety ctx))

    -- Shift preferences
    mapM_ (\(WorkerId wid, shifts) ->
        mapM_ (\(rank, sname) ->
            execute conn
                "INSERT INTO worker_shift_prefs (worker_id, shift_name, rank) VALUES (?, ?, ?)"
                (wid, sname, rank)
            ) (zip [(0::Int)..] shifts)
        ) (Map.toList (wcShiftPrefs ctx))

    -- Weekend-only
    mapM_ (\(WorkerId wid) ->
        execute conn "INSERT INTO worker_weekend_only (worker_id) VALUES (?)"
            (Only wid)
        ) (Set.toList (wcWeekendOnly ctx))

    -- Seniority
    sqlSaveSeniority conn (wcSeniority ctx)

    -- Cross-training goals
    sqlSaveCrossTraining conn (wcCrossTraining ctx)

    -- Pairing preferences
    sqlSavePairing conn "worker_avoid_pairing" (wcAvoidPairing ctx)
    sqlSavePairing conn "worker_prefer_pairing" (wcPreferPairing ctx)

sqlLoadWorkerCtx :: Connection -> IO WorkerContext
sqlLoadWorkerCtx conn = do
    -- Determine active worker IDs (we restrict every map/set below to these).
    activeRows <- query_ conn "SELECT id FROM users WHERE worker_status = 'active'"
        :: IO [Only Int]
    let active = Set.fromList [WorkerId w | Only w <- activeRows]
        keepK m = Map.filterWithKey (\k _ -> Set.member k active) m
        keepS s = Set.intersection s active

    -- Max weekly hours
    hRows <- query_ conn "SELECT worker_id, max_period_seconds FROM worker_hours"
        :: IO [(Int, Int)]
    let maxHours = keepK $ Map.fromList
            [(WorkerId w, secondsToDiffTime s) | (w, s) <- hRows]

    -- Overtime opt-in
    oRows <- query_ conn "SELECT worker_id FROM worker_overtime_optin"
        :: IO [Only Int]
    let overtime = keepS $ Set.fromList [WorkerId w | Only w <- oRows]

    -- Station preferences (ordered by rank)
    pRows <- query_ conn
        "SELECT worker_id, station_id FROM worker_station_prefs ORDER BY worker_id, rank"
        :: IO [(Int, Int)]
    let prefs = keepK $ Map.fromListWith (++)
            [(WorkerId w, [StationId s]) | (w, s) <- pRows]

    -- Prefers variety
    vRows <- query_ conn "SELECT worker_id FROM worker_prefers_variety"
        :: IO [Only Int]
    let variety = keepS $ Set.fromList [WorkerId w | Only w <- vRows]

    -- Shift preferences
    spRows <- query_ conn
        "SELECT worker_id, shift_name FROM worker_shift_prefs ORDER BY worker_id, rank"
        :: IO [(Int, Text)]
    let shiftPrefs = keepK $ Map.fromListWith (++) [(WorkerId w, [s]) | (w, s) <- spRows]

    -- Weekend-only
    woRows <- query_ conn "SELECT worker_id FROM worker_weekend_only"
        :: IO [Only Int]
    let weekendOnly = keepS $ Set.fromList [WorkerId w | Only w <- woRows]

    -- Seniority
    seniority <- keepK <$> sqlLoadSeniority conn

    -- Cross-training goals
    crossTraining <- keepK <$> sqlLoadCrossTraining conn

    -- Pairing preferences (filter both keys and values: only keep relationships
    -- among active workers).
    let restrictPair :: Map.Map WorkerId (Set.Set WorkerId)
                     -> Map.Map WorkerId (Set.Set WorkerId)
        restrictPair m =
            let stripped = Map.map (`Set.intersection` active) (keepK m)
            in Map.filter (not . Set.null) stripped
    avoidPairing  <- restrictPair <$> sqlLoadPairing conn "worker_avoid_pairing"
    preferPairing <- restrictPair <$> sqlLoadPairing conn "worker_prefer_pairing"

    -- Employment status (already filtered to active by sqlLoadEmployment)
    (otModels, ppTracking, tempSet) <- sqlLoadEmployment conn

    return WorkerContext
        { wcMaxPeriodHours = maxHours
        , wcOvertimeOptIn  = overtime
        , wcStationPrefs   = prefs
        , wcPrefersVariety = variety
        , wcShiftPrefs     = shiftPrefs
        , wcWeekendOnly    = weekendOnly
        , wcSeniority      = seniority
        , wcCrossTraining  = crossTraining
        , wcAvoidPairing   = avoidPairing
        , wcPreferPairing  = preferPairing
        , wcOvertimeModel  = otModels
        , wcPayPeriodTracking = ppTracking
        , wcIsTemp         = tempSet
        }

-- =====================================================================
-- Worker employment status
-- =====================================================================

-- | Load all employment records into maps.
sqlLoadEmployment :: Connection
                  -> IO (Map.Map WorkerId OvertimeModel,
                         Map.Map WorkerId PayPeriodTracking,
                         Set.Set WorkerId)
sqlLoadEmployment conn = do
    rows <- query_ conn
        "SELECT we.worker_id, we.overtime_model, we.pay_period_tracking, we.is_temp \
        \FROM worker_employment we \
        \JOIN users u ON u.id = we.worker_id \
        \WHERE u.worker_status = 'active'"
        :: IO [(Int, String, String, Int)]
    let otMap = Map.fromList
            [(WorkerId w, textToOvertimeModel om) | (w, om, _, _) <- rows]
        ppMap = Map.fromList
            [(WorkerId w, textToPayPeriodTracking pp) | (w, _, pp, _) <- rows]
        tempSet = Set.fromList
            [WorkerId w | (w, _, _, t) <- rows, t /= 0]
    return (otMap, ppMap, tempSet)

-- | Upsert a single worker's employment record.
sqlSaveEmployment :: Connection -> WorkerId -> OvertimeModel -> PayPeriodTracking -> Bool -> IO ()
sqlSaveEmployment conn (WorkerId wid) om pp temp =
    execute conn
        "INSERT OR REPLACE INTO worker_employment \
        \(worker_id, overtime_model, pay_period_tracking, is_temp) VALUES (?, ?, ?, ?)"
        (wid, overtimeModelToText om, payPeriodTrackingToText pp, if temp then (1::Int) else 0)

overtimeModelToText :: OvertimeModel -> String
overtimeModelToText OTEligible   = "eligible"
overtimeModelToText OTManualOnly = "manual-only"
overtimeModelToText OTExempt     = "exempt"

textToOvertimeModel :: String -> OvertimeModel
textToOvertimeModel "manual-only" = OTManualOnly
textToOvertimeModel "exempt"      = OTExempt
textToOvertimeModel _             = OTEligible

payPeriodTrackingToText :: PayPeriodTracking -> String
payPeriodTrackingToText PPStandard = "standard"
payPeriodTrackingToText PPExempt   = "exempt"

textToPayPeriodTracking :: String -> PayPeriodTracking
textToPayPeriodTracking "exempt" = PPExempt
textToPayPeriodTracking _        = PPStandard

-- =====================================================================
-- Absence context
-- =====================================================================

sqlSaveAbsenceCtx :: Connection -> AbsenceContext -> IO ()
sqlSaveAbsenceCtx conn ctx = withTransaction conn $ do
    execute_ conn "DELETE FROM absence_types"
    execute_ conn "DELETE FROM absence_requests"
    execute_ conn "DELETE FROM yearly_allowances"

    -- Absence types
    mapM_ (\(AbsenceTypeId tid, at) ->
        execute conn "INSERT INTO absence_types (id, name, yearly_limit) VALUES (?, ?, ?)"
            (tid, atName at, if atYearlyLimit at then (1::Int) else 0)
        ) (Map.toList (acTypes ctx))

    -- Absence requests
    mapM_ (\(AbsenceId aid, ar) -> do
        let AbsenceTypeId tid = arType ar
            WorkerId wid = arWorker ar
        execute conn
            "INSERT INTO absence_requests (id, worker_id, type_id, start_day, end_day, status) \
            \VALUES (?, ?, ?, ?, ?, ?)"
            (aid, wid, tid, dayToText (arStartDay ar), dayToText (arEndDay ar), statusToText (arStatus ar))
        ) (Map.toList (acRequests ctx))

    -- Yearly allowances
    mapM_ (\((WorkerId wid, AbsenceTypeId tid), days) ->
        execute conn
            "INSERT INTO yearly_allowances (worker_id, type_id, days) VALUES (?, ?, ?)"
            (wid, tid, days)
        ) (Map.toList (acYearlyAllowance ctx))

sqlLoadAbsenceCtx :: Connection -> IO AbsenceContext
sqlLoadAbsenceCtx conn = do
    -- Absence types
    tRows <- query_ conn "SELECT id, name, yearly_limit FROM absence_types"
        :: IO [(Int, Text, Int)]
    let types = Map.fromList
            [(AbsenceTypeId tid, AbsenceType nm (lim /= 0))
            | (tid, nm, lim) <- tRows]

    -- Absence requests
    rRows <- query_ conn
        "SELECT id, worker_id, type_id, start_day, end_day, status FROM absence_requests"
        :: IO [(Int, Int, Int, Text, Text, Text)]
    let requests = Map.fromList
            [(AbsenceId aid, AbsenceRequest
                { arId       = AbsenceId aid
                , arWorker   = WorkerId wid
                , arType     = AbsenceTypeId tid
                , arStartDay = textToDay sd
                , arEndDay   = textToDay ed
                , arStatus   = textToStatus st
                })
            | (aid, wid, tid, sd, ed, st) <- rRows]

    -- Next ID
    let nextId = if Map.null requests
                 then 1
                 else let AbsenceId maxId = maximum (Map.keys requests)
                      in maxId + 1

    -- Yearly allowances
    aRows <- query_ conn "SELECT worker_id, type_id, days FROM yearly_allowances"
        :: IO [(Int, Int, Int)]
    let allowances = Map.fromList
            [((WorkerId wid, AbsenceTypeId tid), d) | (wid, tid, d) <- aRows]

    return AbsenceContext
        { acTypes           = types
        , acRequests        = requests
        , acYearlyAllowance = allowances
        , acNextId          = nextId
        }

-- =====================================================================
-- Shifts
-- =====================================================================

sqlSaveShift :: Connection -> ShiftDef -> IO ()
sqlSaveShift conn sd =
    execute conn
        "INSERT OR REPLACE INTO shifts (name, start_hour, end_hour) VALUES (?, ?, ?)"
        (sdName sd, sdStart sd, sdEnd sd)

sqlDeleteShift :: Connection -> Text -> IO ()
sqlDeleteShift conn name =
    execute conn "DELETE FROM shifts WHERE name = ?" (Only name)

sqlLoadShifts :: Connection -> IO [ShiftDef]
sqlLoadShifts conn = do
    rows <- query_ conn "SELECT name, start_hour, end_hour FROM shifts ORDER BY start_hour, name"
        :: IO [(Text, Int, Int)]
    return [ShiftDef name sh eh | (name, sh, eh) <- rows]

-- =====================================================================
-- Schedules
-- =====================================================================

sqlSaveSchedule :: Connection -> Text -> Schedule -> IO ()
sqlSaveSchedule conn name (Schedule assignments) = withTransaction conn $ do
    -- Upsert the schedule name
    execute conn
        "INSERT OR REPLACE INTO schedules (name, created_at) VALUES (?, datetime('now'))"
        (Only name)
    -- Clear old assignments for this schedule
    execute conn "DELETE FROM assignments WHERE schedule_name = ?" (Only name)
    -- Insert all assignments
    mapM_ (\a -> do
        let WorkerId wid = assignWorker a
            StationId sid = assignStation a
            s = assignSlot a
        execute conn
            "INSERT INTO assignments \
            \(schedule_name, worker_id, station_id, slot_date, slot_start, slot_duration_seconds) \
            \VALUES (?, ?, ?, ?, ?, ?)"
            (name, wid, sid, dayToText (slotDate s), todToText (slotStart s),
             diffTimeToSeconds (slotDuration s))
        ) (Set.toList assignments)

sqlLoadSchedule :: Connection -> Text -> IO (Maybe Schedule)
sqlLoadSchedule conn name = do
    exists <- query conn "SELECT 1 FROM schedules WHERE name = ?" (Only name)
        :: IO [Only Int]
    case exists of
        [] -> return Nothing
        _  -> do
            rows <- query conn
                "SELECT worker_id, station_id, slot_date, slot_start, slot_duration_seconds \
                \FROM assignments WHERE schedule_name = ?"
                (Only name)
                :: IO [(Int, Int, Text, Text, Int)]
            let as = Set.fromList
                    [Assignment (WorkerId w) (StationId st)
                        (Slot (textToDay d) (textToTod t) (secondsToDiffTime dur))
                    | (w, st, d, t, dur) <- rows]
            return (Just (Schedule as))

sqlListSchedules :: Connection -> IO [Text]
sqlListSchedules conn = do
    rows <- query_ conn "SELECT name FROM schedules ORDER BY created_at DESC"
        :: IO [Only Text]
    return [n | Only n <- rows]

sqlDeleteSchedule :: Connection -> Text -> IO ()
sqlDeleteSchedule conn name = do
    execute conn "DELETE FROM assignments WHERE schedule_name = ?" (Only name)
    execute conn "DELETE FROM schedules WHERE name = ?" (Only name)

-- =====================================================================
-- Audit log
-- =====================================================================

sqlLogCommandWithMeta :: Connection -> Text -> Text -> Text -> CommandMeta -> IO ()
sqlLogCommandWithMeta conn username command source meta =
    let mut = if cmIsMutation meta then (1 :: Int) else 0
    in execute conn
        "INSERT INTO audit_log (username, command, entity_type, operation, \
        \entity_id, target_id, date_from, date_to, is_mutation, params, source) \
        \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ( ( username, command
          , cmEntityType meta, cmOperation meta
          , cmEntityId meta, cmTargetId meta
          , cmDateFrom meta, cmDateTo meta
          , mut, cmParams meta
          ) :. Only source
        )

sqlGetAuditLog :: Connection -> IO [AuditEntry]
sqlGetAuditLog conn = do
    rows <- query_ conn
        "SELECT id, timestamp, username, command, entity_type, operation, \
        \entity_id, target_id, date_from, date_to, is_mutation, params, source \
        \FROM audit_log ORDER BY id ASC"
        :: IO [(Int, Text, Text, Maybe Text, Maybe Text, Maybe Text,
                Maybe Int) :. (Maybe Int, Maybe Text, Maybe Text, Int, Maybe Text, Text)]
    return [AuditEntry
        { aeId         = i
        , aeTimestamp  = ts
        , aeUsername   = user
        , aeCommand    = cmd
        , aeEntityType = et
        , aeOperation  = op
        , aeEntityId   = eid
        , aeTargetId   = tid
        , aeDateFrom   = df
        , aeDateTo     = dt
        , aeIsMutation = mut /= (0 :: Int)
        , aeParams     = ps
        , aeSource     = src
        } | (i, ts, user, cmd, et, op, eid) :. (tid, df, dt, mut, ps, src) <- rows]

-- =====================================================================
-- Scheduler config
-- =====================================================================

sqlSaveSchedulerConfig :: Connection -> SchedulerConfig -> IO ()
sqlSaveSchedulerConfig conn cfg = withTransaction conn $ do
    execute_ conn "DELETE FROM scheduler_config"
    mapM_ (\(k, v) ->
        execute conn "INSERT INTO scheduler_config (key, value) VALUES (?, ?)" (k, v)
        ) (Map.toList (configToMap cfg))

sqlLoadSchedulerConfig :: Connection -> IO SchedulerConfig
sqlLoadSchedulerConfig conn = do
    rows <- query_ conn "SELECT key, value FROM scheduler_config"
        :: IO [(String, Double)]
    return $ configFromMap (Map.fromList rows)

-- =====================================================================
-- Pay period config
-- =====================================================================

-- | Load the single pay period config row, if present.
sqlLoadPayPeriodConfig :: Connection -> IO (Maybe PayPeriodConfig)
sqlLoadPayPeriodConfig conn = do
    rows <- query_ conn "SELECT period_type, anchor_date FROM pay_period_config LIMIT 1"
        :: IO [(Text, Text)]
    return $ case rows of
        [(pt, ad)] -> case parsePayPeriodType (T.unpack pt) of
            Just ptype -> Just (PayPeriodConfig ptype (textToDay ad))
            Nothing    -> Nothing
        _ -> Nothing

-- | Upsert the single pay period config row.
sqlSavePayPeriodConfig :: Connection -> PayPeriodConfig -> IO ()
sqlSavePayPeriodConfig conn cfg = do
    execute_ conn "DELETE FROM pay_period_config"
    execute conn
        "INSERT INTO pay_period_config (period_type, anchor_date) VALUES (?, ?)"
        (T.pack (showPayPeriodType (ppcType cfg)), dayToText (ppcAnchorDate cfg))

-- =====================================================================
-- Worker seniority
-- =====================================================================

-- | Save seniority data. Does NOT wrap in a transaction — caller must do so
-- (e.g., sqlSaveWorkerCtx already runs inside withTransaction).
sqlSaveSeniority :: Connection -> Map.Map WorkerId Int -> IO ()
sqlSaveSeniority conn m = do
    execute_ conn "DELETE FROM worker_seniority"
    mapM_ (\(WorkerId wid, lvl) ->
        execute conn "INSERT INTO worker_seniority (worker_id, level) VALUES (?, ?)"
            (wid, lvl)
        ) (Map.toList m)

sqlLoadSeniority :: Connection -> IO (Map.Map WorkerId Int)
sqlLoadSeniority conn = do
    rows <- query_ conn "SELECT worker_id, level FROM worker_seniority"
        :: IO [(Int, Int)]
    return $ Map.fromList [(WorkerId w, lvl) | (w, lvl) <- rows]

-- =====================================================================
-- Worker cross-training goals
-- =====================================================================

-- | Save cross-training goals. Does NOT wrap in a transaction — caller must do so.
sqlSaveCrossTraining :: Connection -> Map.Map WorkerId (Set.Set SkillId) -> IO ()
sqlSaveCrossTraining conn m = do
    execute_ conn "DELETE FROM worker_cross_training"
    mapM_ (\(WorkerId wid, skills) ->
        mapM_ (\(SkillId sid) ->
            execute conn "INSERT INTO worker_cross_training (worker_id, skill_id) VALUES (?, ?)"
                (wid, sid)
            ) (Set.toList skills)
        ) (Map.toList m)

sqlLoadCrossTraining :: Connection -> IO (Map.Map WorkerId (Set.Set SkillId))
sqlLoadCrossTraining conn = do
    rows <- query_ conn "SELECT worker_id, skill_id FROM worker_cross_training"
        :: IO [(Int, Int)]
    return $ Map.fromListWith Set.union
        [(WorkerId w, Set.singleton (SkillId s)) | (w, s) <- rows]

-- =====================================================================
-- Worker pairing (avoid / prefer)
-- =====================================================================

-- | Save pairing data to the given table. Does NOT wrap in a transaction.
sqlSavePairing :: Connection -> String -> Map.Map WorkerId (Set.Set WorkerId) -> IO ()
sqlSavePairing conn tableName m = do
    execute_ conn (Query (fromString ("DELETE FROM " ++ tableName)))
    mapM_ (\(WorkerId wid, others) ->
        mapM_ (\(WorkerId oid) ->
            execute conn (Query (fromString
                ("INSERT INTO " ++ tableName ++ " (worker_id, other_id) VALUES (?, ?)")))
                (wid, oid)
            ) (Set.toList others)
        ) (Map.toList m)

sqlLoadPairing :: Connection -> String -> IO (Map.Map WorkerId (Set.Set WorkerId))
sqlLoadPairing conn tableName = do
    rows <- query_ conn (Query (fromString
                ("SELECT worker_id, other_id FROM " ++ tableName)))
        :: IO [(Int, Int)]
    return $ Map.fromListWith Set.union
        [(WorkerId w, Set.singleton (WorkerId o)) | (w, o) <- rows]

-- =====================================================================
-- Pinned assignments
-- =====================================================================

sqlSavePins :: Connection -> [PinnedAssignment] -> IO ()
sqlSavePins conn pins = withTransaction conn $ do
    execute_ conn "DELETE FROM pinned_assignments"
    mapM_ (\p -> do
        let WorkerId wid = pinWorker p
            StationId sid = pinStation p
            dow = showDow (pinDay p)
            (shiftName, hour) = case pinSpec p of
                PinSlot h   -> (Nothing :: Maybe Text, h)
                PinShift sn -> (Just sn, -1)
        execute conn
            "INSERT INTO pinned_assignments (worker_id, station_id, day_of_week, shift_name, hour) \
            \VALUES (?, ?, ?, ?, ?)"
            (wid, sid, dow, shiftName, hour)
        ) pins

sqlLoadPins :: Connection -> IO [PinnedAssignment]
sqlLoadPins conn = do
    rows <- query_ conn
        "SELECT worker_id, station_id, day_of_week, shift_name, hour FROM pinned_assignments"
        :: IO [(Int, Int, String, Maybe Text, Int)]
    return [ PinnedAssignment (WorkerId w) (StationId s) (parseDow d) spec
           | (w, s, d, mShift, h) <- rows
           , let spec = case mShift of
                    Just sn -> PinShift sn
                    Nothing -> PinSlot h
           ]

-- =====================================================================
-- Wipe all data (for demo/replay from scratch)
-- =====================================================================

sqlWipeAll :: Connection -> IO ()
sqlWipeAll conn = withTransaction conn $ do
    -- Order matters for foreign key safety, but we have no FK constraints
    -- in the schema, so just delete everything.
    execute_ conn "DELETE FROM draft_assignments"
    execute_ conn "DELETE FROM drafts"
    execute_ conn "DELETE FROM calendar_commit_assignments"
    execute_ conn "DELETE FROM calendar_commits"
    execute_ conn "DELETE FROM calendar_assignments"
    execute_ conn "DELETE FROM assignments"
    execute_ conn "DELETE FROM schedules"
    execute_ conn "DELETE FROM shifts"
    execute_ conn "DELETE FROM absence_requests"
    execute_ conn "DELETE FROM yearly_allowances"
    execute_ conn "DELETE FROM absence_types"
    execute_ conn "DELETE FROM pinned_assignments"
    execute_ conn "DELETE FROM scheduler_config"
    execute_ conn "DELETE FROM worker_seniority"
    execute_ conn "DELETE FROM worker_cross_training"
    execute_ conn "DELETE FROM worker_avoid_pairing"
    execute_ conn "DELETE FROM worker_prefer_pairing"
    execute_ conn "DELETE FROM pay_period_config"
    execute_ conn "DELETE FROM worker_employment"
    execute_ conn "DELETE FROM station_multi_hours"
    execute_ conn "DELETE FROM worker_weekend_only"
    execute_ conn "DELETE FROM worker_shift_prefs"
    execute_ conn "DELETE FROM worker_prefers_variety"
    execute_ conn "DELETE FROM worker_station_prefs"
    execute_ conn "DELETE FROM worker_overtime_optin"
    execute_ conn "DELETE FROM worker_hours"
    execute_ conn "DELETE FROM worker_skills"
    execute_ conn "DELETE FROM station_required_skills"
    execute_ conn "DELETE FROM station_open_hours"
    execute_ conn "DELETE FROM stations"
    execute_ conn "DELETE FROM skill_implications"
    execute_ conn "DELETE FROM skills"
    execute_ conn "DELETE FROM users"
    -- Reset autoincrement counters
    execute_ conn "DELETE FROM sqlite_sequence"

-- =====================================================================
-- Calendar (continuous assignment store)
-- =====================================================================

-- | Delete existing calendar assignments in date range, insert new ones.
sqlSaveCalendar :: Connection -> Day -> Day -> Schedule -> IO ()
sqlSaveCalendar conn dateFrom dateTo (Schedule assignments) = withTransaction conn $ do
    execute conn
        "DELETE FROM calendar_assignments WHERE slot_date >= ? AND slot_date <= ?"
        (dayToText dateFrom, dayToText dateTo)
    mapM_ (\a -> do
        let WorkerId wid = assignWorker a
            StationId sid = assignStation a
            s = assignSlot a
        execute conn
            "INSERT INTO calendar_assignments \
            \(worker_id, station_id, slot_date, slot_start, slot_duration_seconds) \
            \VALUES (?, ?, ?, ?, ?)"
            (wid, sid, dayToText (slotDate s), todToText (slotStart s),
             diffTimeToSeconds (slotDuration s))
        ) (Set.toList assignments)

-- | Load calendar assignments by date range into a Schedule.
sqlLoadCalendar :: Connection -> Day -> Day -> IO Schedule
sqlLoadCalendar conn dateFrom dateTo = do
    rows <- query conn
        "SELECT worker_id, station_id, slot_date, slot_start, slot_duration_seconds \
        \FROM calendar_assignments WHERE slot_date >= ? AND slot_date <= ?"
        (dayToText dateFrom, dayToText dateTo)
        :: IO [(Int, Int, Text, Text, Int)]
    let as = Set.fromList
            [Assignment (WorkerId w) (StationId st)
                (Slot (textToDay d) (textToTod t) (secondsToDiffTime dur))
            | (w, st, d, t, dur) <- rows]
    return (Schedule as)

-- | Insert commit metadata and snapshot assignments, return commit id.
sqlSaveCommit :: Connection -> Day -> Day -> Text -> Schedule -> IO Int
sqlSaveCommit conn dateFrom dateTo note (Schedule assignments) = withTransaction conn $ do
    execute conn
        "INSERT INTO calendar_commits (committed_at, date_from, date_to, note) \
        \VALUES (strftime('%Y-%m-%d %H:%M:%f', 'now'), ?, ?, ?)"
        (dayToText dateFrom, dayToText dateTo, note)
    commitId <- fromIntegral <$> lastInsertRowId conn
    mapM_ (\a -> do
        let WorkerId wid = assignWorker a
            StationId sid = assignStation a
            s = assignSlot a
        execute conn
            "INSERT INTO calendar_commit_assignments \
            \(commit_id, worker_id, station_id, slot_date, slot_start, slot_duration_seconds) \
            \VALUES (?, ?, ?, ?, ?, ?)"
            (commitId, wid, sid, dayToText (slotDate s), todToText (slotStart s),
             diffTimeToSeconds (slotDuration s))
        ) (Set.toList assignments)
    return commitId

-- | List commits in reverse chronological order.
sqlListCommits :: Connection -> IO [CalendarCommit]
sqlListCommits conn = do
    rows <- query_ conn
        "SELECT id, committed_at, date_from, date_to, note \
        \FROM calendar_commits ORDER BY id DESC"
        :: IO [(Int, Text, Text, Text, Text)]
    return [CalendarCommit cid ts (textToDay df) (textToDay dt) n
           | (cid, ts, df, dt, n) <- rows]

sqlLoadCommitAssignments :: Connection -> Int -> IO Schedule
sqlLoadCommitAssignments conn commitId = do
    rows <- query conn
        "SELECT worker_id, station_id, slot_date, slot_start, slot_duration_seconds \
        \FROM calendar_commit_assignments WHERE commit_id = ?"
        (Only commitId)
        :: IO [(Int, Int, Text, Text, Int)]
    let as = Set.fromList
            [Assignment (WorkerId w) (StationId st)
                (Slot (textToDay d) (textToTod t) (secondsToDiffTime dur))
            | (w, st, d, t, dur) <- rows]
    return (Schedule as)

showDow :: DayOfWeek -> String
showDow Monday    = "monday"
showDow Tuesday   = "tuesday"
showDow Wednesday = "wednesday"
showDow Thursday  = "thursday"
showDow Friday    = "friday"
showDow Saturday  = "saturday"
showDow Sunday    = "sunday"

-- =====================================================================
-- Drafts (staging area for schedule work)
-- =====================================================================

-- | Create a draft for a date range, return the draft_id.
sqlCreateDraft :: Connection -> Day -> Day -> IO Int
sqlCreateDraft conn dateFrom dateTo = do
    execute conn
        "INSERT INTO drafts (date_from, date_to, created_at, last_validated_at) \
        \VALUES (?, ?, strftime('%Y-%m-%d %H:%M:%f', 'now'), strftime('%Y-%m-%d %H:%M:%f', 'now'))"
        (dayToText dateFrom, dayToText dateTo)
    fromIntegral <$> lastInsertRowId conn

-- | Delete a draft and all its assignments.
sqlDeleteDraft :: Connection -> Int -> IO ()
sqlDeleteDraft conn draftId = do
    execute conn "DELETE FROM draft_assignments WHERE draft_id = ?" (Only draftId)
    execute conn "DELETE FROM drafts WHERE draft_id = ?" (Only draftId)

-- | List all drafts ordered by created_at.
sqlListDrafts :: Connection -> IO [DraftInfo]
sqlListDrafts conn = do
    rows <- query_ conn
        "SELECT draft_id, date_from, date_to, created_at, last_validated_at \
        \FROM drafts ORDER BY created_at"
        :: IO [(Int, Text, Text, Text, Text)]
    return [DraftInfo did (textToDay df) (textToDay dt) ts lv
           | (did, df, dt, ts, lv) <- rows]

sqlGetDraft :: Connection -> Int -> IO (Maybe DraftInfo)
sqlGetDraft conn draftId = do
    rows <- query conn
        "SELECT draft_id, date_from, date_to, created_at, last_validated_at \
        \FROM drafts WHERE draft_id = ?"
        (Only draftId)
        :: IO [(Int, Text, Text, Text, Text)]
    return $ case rows of
        [(did, df, dt, ts, lv)] -> Just (DraftInfo did (textToDay df) (textToDay dt) ts lv)
        _                       -> Nothing

-- | Check if a date range overlaps any existing draft.
sqlCheckDraftOverlap :: Connection -> Day -> Day -> IO Bool
sqlCheckDraftOverlap conn dateFrom dateTo = do
    rows <- query conn
        "SELECT 1 FROM drafts WHERE date_from <= ? AND date_to >= ?"
        (dayToText dateTo, dayToText dateFrom)
        :: IO [Only Int]
    return (not (null rows))

-- | Save assignments for a draft (delete existing, insert new).
sqlSaveDraftAssignments :: Connection -> Int -> Schedule -> IO ()
sqlSaveDraftAssignments conn draftId (Schedule assignments) = withTransaction conn $ do
    execute conn "DELETE FROM draft_assignments WHERE draft_id = ?" (Only draftId)
    mapM_ (\a -> do
        let WorkerId wid = assignWorker a
            StationId sid = assignStation a
            s = assignSlot a
        execute conn
            "INSERT INTO draft_assignments \
            \(draft_id, worker_id, station_id, slot_date, slot_start, slot_duration_seconds) \
            \VALUES (?, ?, ?, ?, ?, ?)"
            (draftId, wid, sid, dayToText (slotDate s), todToText (slotStart s),
             diffTimeToSeconds (slotDuration s))
        ) (Set.toList assignments)

-- | Load assignments for a draft as a Schedule.
sqlLoadDraftAssignments :: Connection -> Int -> IO Schedule
sqlLoadDraftAssignments conn draftId = do
    rows <- query conn
        "SELECT worker_id, station_id, slot_date, slot_start, slot_duration_seconds \
        \FROM draft_assignments WHERE draft_id = ?"
        (Only draftId)
        :: IO [(Int, Int, Text, Text, Int)]
    let as = Set.fromList
            [Assignment (WorkerId w) (StationId st)
                (Slot (textToDay d) (textToTod t) (secondsToDiffTime dur))
            | (w, st, d, t, dur) <- rows]
    return (Schedule as)

sqlCalendarCommitsAfter :: Connection -> Text -> IO [CalendarCommit]
sqlCalendarCommitsAfter conn ts = do
    rows <- query conn
        "SELECT id, committed_at, date_from, date_to, note \
        \FROM calendar_commits WHERE committed_at > ? ORDER BY id DESC"
        (Only ts)
        :: IO [(Int, Text, Text, Text, Text)]
    return [CalendarCommit cid ca (textToDay df) (textToDay dt) n
           | (cid, ca, df, dt, n) <- rows]

-- | Update a draft's last_validated_at to the current time.
sqlUpdateDraftValidatedAt :: Connection -> Int -> IO ()
sqlUpdateDraftValidatedAt conn draftId =
    execute conn
        "UPDATE drafts SET last_validated_at = strftime('%Y-%m-%d %H:%M:%f', 'now') WHERE draft_id = ?"
        (Only draftId)

-- =====================================================================
-- Checkpoint (SQLite savepoints)
-- =====================================================================

sqlSavepoint :: Connection -> Text -> IO ()
sqlSavepoint conn name =
    execute_ conn (Query (fromString ("SAVEPOINT \"" ++ T.unpack (sanitize name) ++ "\"")))

sqlRelease :: Connection -> Text -> IO ()
sqlRelease conn name =
    execute_ conn (Query (fromString ("RELEASE SAVEPOINT \"" ++ T.unpack (sanitize name) ++ "\"")))

sqlRollbackTo :: Connection -> Text -> IO ()
sqlRollbackTo conn name =
    execute_ conn (Query (fromString ("ROLLBACK TO SAVEPOINT \"" ++ T.unpack (sanitize name) ++ "\"")))

sanitize :: Text -> Text
sanitize = T.filter (/= '"')

-- =====================================================================
-- Sessions
-- =====================================================================

sqlCreateSession :: Connection -> UserId -> IO (SessionId, Text)
sqlCreateSession conn (UserId uid) = do
    tok <- generateToken
    execute conn "INSERT INTO sessions (user_id, token) VALUES (?, ?)" (uid, tok)
    sid <- lastInsertRowId conn
    return (SessionId (fromIntegral sid), tok)

sqlGetActiveSession :: Connection -> UserId -> IO (Maybe SessionId)
sqlGetActiveSession conn (UserId uid) = do
    rows <- query conn
        "SELECT id FROM sessions WHERE user_id = ? AND is_active = 1 \
        \ORDER BY id DESC LIMIT 1"
        (Only uid)
        :: IO [Only Int]
    return $ case rows of
        [Only sid] -> Just (SessionId sid)
        _          -> Nothing

sqlTouchSession :: Connection -> SessionId -> IO ()
sqlTouchSession conn (SessionId sid) =
    execute conn
        "UPDATE sessions SET last_active_at = datetime('now') WHERE id = ?"
        (Only sid)

sqlCloseSession :: Connection -> SessionId -> IO ()
sqlCloseSession conn (SessionId sid) =
    execute conn
        "UPDATE sessions SET is_active = 0 WHERE id = ?"
        (Only sid)

sqlGetSessionByToken :: Connection -> Text -> IO (Maybe (SessionId, UserId, UTCTime))
sqlGetSessionByToken conn tok = do
    rows <- query conn
        "SELECT id, user_id, last_active_at FROM sessions \
        \WHERE token = ? AND is_active = 1 LIMIT 1"
        (Only tok)
        :: IO [(Int, Int, Text)]
    return $ case rows of
        [(sid, uid, la)] -> case parseUTCTime la of
            Just t  -> Just (SessionId sid, UserId uid, t)
            Nothing -> Nothing
        _ -> Nothing

parseUTCTime :: Text -> Maybe UTCTime
parseUTCTime s =
    parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S" (T.unpack s)

-- | Get the user ID that owns a session.
sqlGetSessionOwner :: Connection -> SessionId -> IO (Maybe UserId)
sqlGetSessionOwner conn (SessionId sid) = do
    rows <- query conn
        "SELECT user_id FROM sessions WHERE id = ?"
        (Only sid)
        :: IO [Only Int]
    return $ case rows of
        [Only uid] -> Just (UserId uid)
        _          -> Nothing

-- | Get the idle timeout in minutes from scheduler_config (default 30).
sqlGetIdleTimeoutMinutes :: Connection -> IO Double
sqlGetIdleTimeoutMinutes conn = do
    rows <- query conn
        "SELECT value FROM scheduler_config WHERE key = ?"
        (Only ("session_idle_timeout_minutes" :: Text))
        :: IO [Only Double]
    return $ case rows of
        [Only v] -> v
        _        -> 30.0

-- | Generate a random 64-character hex token (32 bytes of entropy).
generateToken :: IO Text
generateToken = do
    bytes <- mapM (\_ -> randomRIO (0, 255 :: Int)) [(1::Int)..32]
    return $ T.pack $ concatMap (\b -> let h = showHex b "" in if b < 16 then '0':h else h) bytes

-- =====================================================================
-- Hint sessions
-- =====================================================================

sqlSaveHintSession :: Connection -> SessionId -> Int -> [Hint] -> Int -> IO ()
sqlSaveHintSession conn (SessionId sid) draftId hints checkpoint =
    execute conn
        "INSERT INTO hint_sessions (session_id, draft_id, hints_json, checkpoint, updated_at) \
        \VALUES (?, ?, ?, ?, datetime('now')) \
        \ON CONFLICT (session_id, draft_id) DO UPDATE SET \
        \  hints_json = excluded.hints_json, \
        \  checkpoint = excluded.checkpoint, \
        \  updated_at = datetime('now')"
        (sid, draftId, hintsText, checkpoint)
  where
    hintsText = T.unpack (decodeUtf8 (BL.toStrict (encodeHints hints)))

sqlLoadHintSession :: Connection -> SessionId -> Int -> IO (Maybe HintSessionRecord)
sqlLoadHintSession conn (SessionId sid) draftId = do
    rows <- query conn
        "SELECT hints_json, checkpoint FROM hint_sessions \
        \WHERE session_id = ? AND draft_id = ?"
        (sid, draftId)
        :: IO [(String, Int)]
    case rows of
        [(json, cp)] -> case decodeHints (BL.fromStrict (encodeUtf8 (T.pack json))) of
            Just hints -> return (Just (HintSessionRecord hints cp))
            Nothing    -> return Nothing  -- deserialization failure
        _ -> return Nothing

sqlDeleteHintSession :: Connection -> SessionId -> Int -> IO ()
sqlDeleteHintSession conn (SessionId sid) draftId =
    execute conn
        "DELETE FROM hint_sessions WHERE session_id = ? AND draft_id = ?"
        (sid, draftId)

-- =====================================================================
-- Audit log (extended queries)
-- =====================================================================

sqlAuditSince :: Connection -> Int -> IO [AuditEntry]
sqlAuditSince conn checkpoint = do
    rows <- query conn
        "SELECT id, timestamp, username, command, entity_type, operation, \
        \entity_id, target_id, date_from, date_to, is_mutation, params, source \
        \FROM audit_log WHERE id > ? AND is_mutation = 1 ORDER BY id ASC"
        (Only checkpoint)
        :: IO [(Int, Text, Text, Maybe Text, Maybe Text, Maybe Text,
                Maybe Int) :. (Maybe Int, Maybe Text, Maybe Text, Int, Maybe Text, Text)]
    return [AuditEntry
        { aeId         = i
        , aeTimestamp  = ts
        , aeUsername   = user
        , aeCommand    = cmd
        , aeEntityType = et
        , aeOperation  = op
        , aeEntityId   = eid
        , aeTargetId   = tid
        , aeDateFrom   = df
        , aeDateTo     = dt
        , aeIsMutation = mut /= (0 :: Int)
        , aeParams     = ps
        , aeSource     = src
        } | (i, ts, user, cmd, et, op, eid) :. (tid, df, dt, mut, ps, src) <- rows]

-- =====================================================================
-- Helpers
-- =====================================================================

parseDow :: String -> DayOfWeek
parseDow "monday"    = Monday
parseDow "tuesday"   = Tuesday
parseDow "wednesday" = Wednesday
parseDow "thursday"  = Thursday
parseDow "friday"    = Friday
parseDow "saturday"  = Saturday
parseDow "sunday"    = Sunday
parseDow _           = Monday  -- fallback
