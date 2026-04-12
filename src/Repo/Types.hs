module Repo.Types
    ( Repository(..)
    , CalendarCommit(..)
    , DraftInfo(..)
    , AuditEntry(..)
    , SessionId(..)
    ) where

import Auth.Types (UserId, Role, User)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time (Day)
import Domain.Types (WorkerId, StationId, SkillId, Schedule)
import Domain.Shift (ShiftDef)
import Domain.Skill (Skill, SkillContext)
import Domain.Worker (WorkerContext, OvertimeModel, PayPeriodTracking)
import Domain.Absence (AbsenceContext)
import Domain.SchedulerConfig (SchedulerConfig)
import Domain.Pin (PinnedAssignment)
import Domain.PayPeriod (PayPeriodConfig)

-- | Opaque session identifier.
newtype SessionId = SessionId Int
    deriving (Eq, Ord, Show)

-- | Metadata for a draft session.
data DraftInfo = DraftInfo
    { diId             :: !Int
    , diDateFrom       :: !Day
    , diDateTo         :: !Day
    , diCreatedAt      :: !String
    , diLastValidatedAt :: !String
    } deriving (Show, Eq)

-- | Metadata for a calendar history commit.
data CalendarCommit = CalendarCommit
    { ccId          :: !Int
    , ccCommittedAt :: !String
    , ccDateFrom    :: !Day
    , ccDateTo      :: !Day
    , ccNote        :: !String
    } deriving (Show)

-- | Structured audit log entry.
data AuditEntry = AuditEntry
    { aeId         :: !Int
    , aeTimestamp  :: !String
    , aeUsername   :: !String
    , aeCommand    :: !(Maybe String)
    , aeEntityType :: !(Maybe String)
    , aeOperation  :: !(Maybe String)
    , aeEntityId   :: !(Maybe Int)
    , aeTargetId   :: !(Maybe Int)
    , aeDateFrom   :: !(Maybe String)
    , aeDateTo     :: !(Maybe String)
    , aeIsMutation :: !Bool
    , aeParams     :: !(Maybe String)
    , aeSource     :: !String
    } deriving (Show, Eq)

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
      -- Worker employment status
      -- ---------------------------------------------------------------
    , repoLoadEmployment :: IO (Map.Map WorkerId OvertimeModel,
                                Map.Map WorkerId PayPeriodTracking,
                                Set.Set WorkerId)
      -- ^ Load all employment records: (overtime models, pay tracking, temp flags)
    , repoSaveEmployment :: WorkerId -> OvertimeModel -> PayPeriodTracking -> Bool -> IO ()
      -- ^ Upsert a single worker's employment record

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
      -- Pay period config
      -- ---------------------------------------------------------------
    , repoLoadPayPeriodConfig :: IO (Maybe PayPeriodConfig)
      -- ^ Load pay period config; Nothing if not configured
    , repoSavePayPeriodConfig :: PayPeriodConfig -> IO ()
      -- ^ Upsert the single pay period config row

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
    , repoGetAuditLog    :: IO [AuditEntry]
      -- ^ returns structured audit entries
    , repoWipeAll        :: IO ()
      -- ^ delete all data from all tables (for demo/replay)

      -- ---------------------------------------------------------------
      -- Calendar (continuous assignment store)
      -- ---------------------------------------------------------------
    , repoSaveCalendar   :: Day -> Day -> Schedule -> IO ()
      -- ^ Save calendar assignments for a date range (delete existing in range, insert new)
    , repoLoadCalendar   :: Day -> Day -> IO Schedule
      -- ^ Load calendar assignments by date range
    , repoSaveCommit     :: Day -> Day -> String -> Schedule -> IO Int
      -- ^ Save a history commit with snapshot of old assignments, return commit id
    , repoListCommits    :: IO [CalendarCommit]
      -- ^ List calendar commits in reverse chronological order
    , repoLoadCommitAssignments :: Int -> IO Schedule
      -- ^ Load snapshot assignments for a commit id

      -- ---------------------------------------------------------------
      -- Drafts (staging area for schedule work)
      -- ---------------------------------------------------------------
    , repoCreateDraft    :: Day -> Day -> IO Int
      -- ^ Create a draft for a date range, return draft_id
    , repoDeleteDraft    :: Int -> IO ()
      -- ^ Delete a draft and its assignments
    , repoListDrafts     :: IO [DraftInfo]
      -- ^ List all active drafts
    , repoGetDraft       :: Int -> IO (Maybe DraftInfo)
      -- ^ Get draft metadata by id
    , repoCheckDraftOverlap :: Day -> Day -> IO Bool
      -- ^ Check if a date range overlaps any existing draft
    , repoSaveDraftAssignments :: Int -> Schedule -> IO ()
      -- ^ Save assignments for a draft (replace existing)
    , repoLoadDraftAssignments :: Int -> IO Schedule
      -- ^ Load assignments for a draft
    , repoCalendarCommitsAfter :: String -> IO [CalendarCommit]
      -- ^ List calendar commits with committed_at after the given timestamp
    , repoUpdateDraftValidatedAt :: Int -> IO ()
      -- ^ Update a draft's last_validated_at to current time

      -- ---------------------------------------------------------------
      -- Checkpoint (SQLite savepoints)
      -- ---------------------------------------------------------------
    , repoSavepoint      :: String -> IO ()
      -- ^ Create a savepoint with the given name
    , repoRelease        :: String -> IO ()
      -- ^ Release (commit) a savepoint
    , repoRollbackTo     :: String -> IO ()
      -- ^ Rollback to a savepoint (savepoint remains active)

      -- ---------------------------------------------------------------
      -- Sessions
      -- ---------------------------------------------------------------
    , repoCreateSession     :: UserId -> IO SessionId
      -- ^ Create a new active session for a user
    , repoGetActiveSession  :: UserId -> IO (Maybe SessionId)
      -- ^ Get the active session for a user, if any
    , repoTouchSession      :: SessionId -> IO ()
      -- ^ Update last_active_at to current time
    , repoCloseSession      :: SessionId -> IO ()
      -- ^ Mark a session as inactive
    }
