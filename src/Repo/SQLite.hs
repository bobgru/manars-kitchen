{-# LANGUAGE OverloadedStrings #-}
module Repo.SQLite
    ( mkSQLiteRepo
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.String (fromString)
import Database.SQLite.Simple

import Auth.Types (UserId(..), Username(..), Role(..), User(..))
import Domain.Types
    ( WorkerId(..), StationId(..), SkillId(..)
    , AbsenceId(..), AbsenceTypeId(..)
    , Slot(..), Assignment(..), Schedule(..)
    )
import Data.Time (DayOfWeek(..))
import Domain.Shift (ShiftDef(..))
import Domain.Skill (Skill(..), SkillContext(..))
import Domain.Worker (WorkerContext(..))
import Domain.SchedulerConfig (SchedulerConfig, configToMap, configFromMap)
import Domain.Pin (PinnedAssignment(..), PinSpec(..))
import Domain.Absence
    ( AbsenceType(..)
    , AbsenceRequest(..), AbsenceContext(..)
    )
import Repo.Types (Repository(..))
import Repo.Schema (initSchema)
import Repo.Serialize

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
        , repoCreateSkill    = sqlCreateSkill conn
        , repoDeleteSkill    = sqlDeleteSkill conn
        , repoListSkills     = sqlListSkills conn
        , repoCreateStation  = sqlCreateStation conn
        , repoDeleteStation  = sqlDeleteStation conn
        , repoListStations   = sqlListStations conn
        , repoSaveSkillCtx   = sqlSaveSkillCtx conn
        , repoLoadSkillCtx   = sqlLoadSkillCtx conn
        , repoSaveWorkerCtx  = sqlSaveWorkerCtx conn
        , repoLoadWorkerCtx  = sqlLoadWorkerCtx conn
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
        , repoSavePins       = sqlSavePins conn
        , repoLoadPins       = sqlLoadPins conn
        , repoLogCommand     = sqlLogCommand conn
        , repoGetAuditLog    = sqlGetAuditLog conn
        , repoWipeAll        = sqlWipeAll conn
        , repoSavepoint      = sqlSavepoint conn
        , repoRelease        = sqlRelease conn
        , repoRollbackTo     = sqlRollbackTo conn
        })

-- =====================================================================
-- Users
-- =====================================================================

sqlCreateUser :: Connection -> String -> String -> Role -> WorkerId -> IO UserId
sqlCreateUser conn name passHash role (WorkerId wid) = do
    execute conn
        "INSERT INTO users (username, password_hash, role, worker_id) VALUES (?, ?, ?, ?)"
        (name, passHash, roleToText role, wid)
    UserId . fromIntegral <$> lastInsertRowId conn

sqlGetUser :: Connection -> UserId -> IO (Maybe User)
sqlGetUser conn (UserId uid) = do
    rows <- query conn
        "SELECT id, username, password_hash, role, worker_id FROM users WHERE id = ?"
        (Only uid)
    return $ case rows of
        [(i, n, h, r, w)] -> Just (toUser i n h r w)
        _                 -> Nothing

sqlGetUserByName :: Connection -> String -> IO (Maybe User)
sqlGetUserByName conn name = do
    rows <- query conn
        "SELECT id, username, password_hash, role, worker_id FROM users WHERE username = ?"
        (Only name)
    return $ case rows of
        [(i, n, h, r, w)] -> Just (toUser i n h r w)
        _                 -> Nothing

sqlUpdatePassword :: Connection -> UserId -> String -> IO ()
sqlUpdatePassword conn (UserId uid) passHash =
    execute conn "UPDATE users SET password_hash = ? WHERE id = ?" (passHash, uid)

sqlListUsers :: Connection -> IO [User]
sqlListUsers conn = do
    rows <- query_ conn "SELECT id, username, password_hash, role, worker_id FROM users"
    return [toUser i n h r w | (i, n, h, r, w) <- rows]

sqlDeleteUser :: Connection -> UserId -> IO ()
sqlDeleteUser conn (UserId uid) =
    execute conn "DELETE FROM users WHERE id = ?" (Only uid)

toUser :: Int -> String -> String -> String -> Int -> User
toUser i n h r w = User
    { userId       = UserId i
    , userName     = Username n
    , userPassHash = h
    , userRole     = textToRole r
    , userWorkerId = WorkerId w
    }

-- =====================================================================
-- Skills (entity CRUD — preserves name/description)
-- =====================================================================

sqlCreateSkill :: Connection -> SkillId -> String -> String -> IO ()
sqlCreateSkill conn (SkillId sid) name desc =
    execute conn
        "INSERT OR REPLACE INTO skills (id, name, description) VALUES (?, ?, ?)"
        (sid, name, desc)

sqlDeleteSkill :: Connection -> SkillId -> IO ()
sqlDeleteSkill conn (SkillId sid) = do
    execute conn "DELETE FROM skill_implications WHERE skill_id = ? OR implies_skill_id = ?" (sid, sid)
    execute conn "DELETE FROM worker_skills WHERE skill_id = ?" (Only sid)
    execute conn "DELETE FROM station_required_skills WHERE skill_id = ?" (Only sid)
    execute conn "DELETE FROM skills WHERE id = ?" (Only sid)

sqlListSkills :: Connection -> IO [(SkillId, Skill)]
sqlListSkills conn = do
    rows <- query_ conn "SELECT id, name, description FROM skills ORDER BY id"
        :: IO [(Int, String, String)]
    return [(SkillId sid, Skill name desc) | (sid, name, desc) <- rows]

-- =====================================================================
-- Stations (entity CRUD)
-- =====================================================================

sqlCreateStation :: Connection -> StationId -> String -> IO ()
sqlCreateStation conn (StationId sid) name =
    execute conn
        "INSERT OR REPLACE INTO stations (id, name) VALUES (?, ?)"
        (sid, name)

sqlDeleteStation :: Connection -> StationId -> IO ()
sqlDeleteStation conn (StationId sid) = do
    execute conn "DELETE FROM station_required_skills WHERE station_id = ?" (Only sid)
    execute conn "DELETE FROM stations WHERE id = ?" (Only sid)

sqlListStations :: Connection -> IO [(StationId, String)]
sqlListStations conn = do
    rows <- query_ conn "SELECT id, name FROM stations ORDER BY id"
        :: IO [(Int, String)]
    return [(StationId sid, name) | (sid, name) <- rows]

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

    -- Ensure stations exist (preserve station names)
    mapM_ (\(StationId sid) ->
        execute conn
            "INSERT OR IGNORE INTO stations (id, name) VALUES (?, ?)"
            (sid, "" :: String)
        ) (Set.toList (scAllStations ctx))

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
        execute conn "INSERT INTO worker_hours (worker_id, max_weekly_seconds) VALUES (?, ?)"
            (wid, diffTimeToSeconds dt)
        ) (Map.toList (wcMaxWeeklyHours ctx))

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
    -- Max weekly hours
    hRows <- query_ conn "SELECT worker_id, max_weekly_seconds FROM worker_hours"
        :: IO [(Int, Int)]
    let maxHours = Map.fromList
            [(WorkerId w, secondsToDiffTime s) | (w, s) <- hRows]

    -- Overtime opt-in
    oRows <- query_ conn "SELECT worker_id FROM worker_overtime_optin"
        :: IO [Only Int]
    let overtime = Set.fromList [WorkerId w | Only w <- oRows]

    -- Station preferences (ordered by rank)
    pRows <- query_ conn
        "SELECT worker_id, station_id FROM worker_station_prefs ORDER BY worker_id, rank"
        :: IO [(Int, Int)]
    let prefs = Map.fromListWith (++)
            [(WorkerId w, [StationId s]) | (w, s) <- pRows]

    -- Prefers variety
    vRows <- query_ conn "SELECT worker_id FROM worker_prefers_variety"
        :: IO [Only Int]
    let variety = Set.fromList [WorkerId w | Only w <- vRows]

    -- Shift preferences
    spRows <- query_ conn
        "SELECT worker_id, shift_name FROM worker_shift_prefs ORDER BY worker_id, rank"
        :: IO [(Int, String)]
    let shiftPrefs = Map.fromListWith (++) [(WorkerId w, [s]) | (w, s) <- spRows]

    -- Weekend-only
    woRows <- query_ conn "SELECT worker_id FROM worker_weekend_only"
        :: IO [Only Int]
    let weekendOnly = Set.fromList [WorkerId w | Only w <- woRows]

    -- Seniority
    seniority <- sqlLoadSeniority conn

    -- Cross-training goals
    crossTraining <- sqlLoadCrossTraining conn

    -- Pairing preferences
    avoidPairing  <- sqlLoadPairing conn "worker_avoid_pairing"
    preferPairing <- sqlLoadPairing conn "worker_prefer_pairing"

    return WorkerContext
        { wcMaxWeeklyHours = maxHours
        , wcOvertimeOptIn  = overtime
        , wcStationPrefs   = prefs
        , wcPrefersVariety = variety
        , wcShiftPrefs     = shiftPrefs
        , wcWeekendOnly    = weekendOnly
        , wcSeniority      = seniority
        , wcCrossTraining  = crossTraining
        , wcAvoidPairing   = avoidPairing
        , wcPreferPairing  = preferPairing
        }

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
        :: IO [(Int, String, Int)]
    let types = Map.fromList
            [(AbsenceTypeId tid, AbsenceType nm (lim /= 0))
            | (tid, nm, lim) <- tRows]

    -- Absence requests
    rRows <- query_ conn
        "SELECT id, worker_id, type_id, start_day, end_day, status FROM absence_requests"
        :: IO [(Int, Int, Int, String, String, String)]
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

sqlDeleteShift :: Connection -> String -> IO ()
sqlDeleteShift conn name =
    execute conn "DELETE FROM shifts WHERE name = ?" (Only name)

sqlLoadShifts :: Connection -> IO [ShiftDef]
sqlLoadShifts conn = do
    rows <- query_ conn "SELECT name, start_hour, end_hour FROM shifts ORDER BY start_hour, name"
        :: IO [(String, Int, Int)]
    return [ShiftDef name sh eh | (name, sh, eh) <- rows]

-- =====================================================================
-- Schedules
-- =====================================================================

sqlSaveSchedule :: Connection -> String -> Schedule -> IO ()
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

sqlLoadSchedule :: Connection -> String -> IO (Maybe Schedule)
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
                :: IO [(Int, Int, String, String, Int)]
            let as = Set.fromList
                    [Assignment (WorkerId w) (StationId st)
                        (Slot (textToDay d) (textToTod t) (secondsToDiffTime dur))
                    | (w, st, d, t, dur) <- rows]
            return (Just (Schedule as))

sqlListSchedules :: Connection -> IO [String]
sqlListSchedules conn = do
    rows <- query_ conn "SELECT name FROM schedules ORDER BY created_at DESC"
        :: IO [Only String]
    return [n | Only n <- rows]

sqlDeleteSchedule :: Connection -> String -> IO ()
sqlDeleteSchedule conn name = do
    execute conn "DELETE FROM assignments WHERE schedule_name = ?" (Only name)
    execute conn "DELETE FROM schedules WHERE name = ?" (Only name)

-- =====================================================================
-- Audit log
-- =====================================================================

sqlLogCommand :: Connection -> String -> String -> IO ()
sqlLogCommand conn username command =
    execute conn "INSERT INTO audit_log (username, command) VALUES (?, ?)"
        (username, command)

sqlGetAuditLog :: Connection -> IO [(String, String, String)]
sqlGetAuditLog conn = do
    rows <- query_ conn
        "SELECT timestamp, username, command FROM audit_log ORDER BY id ASC"
        :: IO [(String, String, String)]
    return rows

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
                PinSlot h   -> (Nothing :: Maybe String, h)
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
        :: IO [(Int, Int, String, Maybe String, Int)]
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

showDow :: DayOfWeek -> String
showDow Monday    = "monday"
showDow Tuesday   = "tuesday"
showDow Wednesday = "wednesday"
showDow Thursday  = "thursday"
showDow Friday    = "friday"
showDow Saturday  = "saturday"
showDow Sunday    = "sunday"

-- =====================================================================
-- Checkpoint (SQLite savepoints)
-- =====================================================================

sqlSavepoint :: Connection -> String -> IO ()
sqlSavepoint conn name =
    execute_ conn (Query (fromString ("SAVEPOINT \"" ++ sanitize name ++ "\"")))

sqlRelease :: Connection -> String -> IO ()
sqlRelease conn name =
    execute_ conn (Query (fromString ("RELEASE SAVEPOINT \"" ++ sanitize name ++ "\"")))

sqlRollbackTo :: Connection -> String -> IO ()
sqlRollbackTo conn name =
    execute_ conn (Query (fromString ("ROLLBACK TO SAVEPOINT \"" ++ sanitize name ++ "\"")))

-- | Basic sanitization: remove quotes to prevent SQL injection.
sanitize :: String -> String
sanitize = filter (/= '"')

parseDow :: String -> DayOfWeek
parseDow "monday"    = Monday
parseDow "tuesday"   = Tuesday
parseDow "wednesday" = Wednesday
parseDow "thursday"  = Thursday
parseDow "friday"    = Friday
parseDow "saturday"  = Saturday
parseDow "sunday"    = Sunday
parseDow _           = Monday  -- fallback
