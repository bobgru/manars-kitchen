module Repo.Types
    ( Repository(..)
    ) where

import Auth.Types (UserId, Role, User)
import Domain.Types (WorkerId, StationId, SkillId, Schedule)
import Domain.Shift (ShiftDef)
import Domain.Skill (Skill, SkillContext)
import Domain.Worker (WorkerContext)
import Domain.Absence (AbsenceContext)
import Domain.SchedulerConfig (SchedulerConfig)
import Domain.Pin (PinnedAssignment)

-- | Record-of-functions abstracting over storage backend.
-- Each field is an IO action; swap the record to swap the backend
-- (e.g., SQLite -> PostgreSQL).
data Repository = Repository
    { -- ---------------------------------------------------------------
      -- Users
      -- ---------------------------------------------------------------
      repoCreateUser     :: String -> String -> Role -> WorkerId -> IO UserId
      -- ^ username, password hash, role, worker id
    , repoGetUser        :: UserId -> IO (Maybe User)
    , repoGetUserByName  :: String -> IO (Maybe User)
    , repoUpdatePassword :: UserId -> String -> IO ()
      -- ^ user id, new password hash
    , repoListUsers      :: IO [User]
    , repoDeleteUser     :: UserId -> IO ()

      -- ---------------------------------------------------------------
      -- Skills (entity CRUD)
      -- ---------------------------------------------------------------
    , repoCreateSkill    :: SkillId -> String -> String -> IO ()
      -- ^ id, name, description
    , repoDeleteSkill    :: SkillId -> IO ()
    , repoListSkills     :: IO [(SkillId, Skill)]

      -- ---------------------------------------------------------------
      -- Stations (entity CRUD)
      -- ---------------------------------------------------------------
    , repoCreateStation  :: StationId -> String -> IO ()
      -- ^ id, name
    , repoDeleteStation  :: StationId -> IO ()
    , repoListStations   :: IO [(StationId, String)]
      -- ^ (id, name)

      -- ---------------------------------------------------------------
      -- Skill context (relational data)
      -- ---------------------------------------------------------------
    , repoSaveSkillCtx   :: SkillContext -> IO ()
    , repoLoadSkillCtx   :: IO SkillContext

      -- ---------------------------------------------------------------
      -- Worker context
      -- ---------------------------------------------------------------
    , repoSaveWorkerCtx  :: WorkerContext -> IO ()
    , repoLoadWorkerCtx  :: IO WorkerContext

      -- ---------------------------------------------------------------
      -- Absence context
      -- ---------------------------------------------------------------
    , repoSaveAbsenceCtx :: AbsenceContext -> IO ()
    , repoLoadAbsenceCtx :: IO AbsenceContext

      -- ---------------------------------------------------------------
      -- Shifts
      -- ---------------------------------------------------------------
    , repoSaveShift      :: ShiftDef -> IO ()
    , repoDeleteShift    :: String -> IO ()
    , repoLoadShifts     :: IO [ShiftDef]

      -- ---------------------------------------------------------------
      -- Schedules
      -- ---------------------------------------------------------------
    , repoSaveSchedule   :: String -> Schedule -> IO ()
      -- ^ Save a schedule under a name (overwrites if exists).
    , repoLoadSchedule   :: String -> IO (Maybe Schedule)
    , repoListSchedules  :: IO [String]
    , repoDeleteSchedule :: String -> IO ()

      -- ---------------------------------------------------------------
      -- Scheduler config
      -- ---------------------------------------------------------------
    , repoSaveSchedulerConfig :: SchedulerConfig -> IO ()
    , repoLoadSchedulerConfig :: IO SchedulerConfig

      -- ---------------------------------------------------------------
      -- Pinned assignments
      -- ---------------------------------------------------------------
    , repoSavePins :: [PinnedAssignment] -> IO ()
    , repoLoadPins :: IO [PinnedAssignment]

      -- ---------------------------------------------------------------
      -- Audit log
      -- ---------------------------------------------------------------
    , repoLogCommand     :: String -> String -> IO ()
      -- ^ username, command string
    , repoGetAuditLog    :: IO [(String, String, String)]
      -- ^ returns (timestamp, username, command)
    , repoWipeAll        :: IO ()
      -- ^ delete all data from all tables (for demo/replay)
    }
