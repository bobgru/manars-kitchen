module Repo.Types
    ( Repository(..)
    , CalendarCommit(..)
    , DraftInfo(..)
    , AuditEntry(..)
    , SessionId(..)
    , Token
    , HintSessionRecord(..)
    ) where

import Auth.Types (UserId, Role, User)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Time (Day, UTCTime)
import Domain.Types (WorkerId, StationId, Station, SkillId, Schedule)
import Domain.Shift (ShiftDef)
import Domain.Skill (Skill, SkillContext)
import Audit.CommandMeta (CommandMeta)
import Domain.Worker (WorkerContext, OvertimeModel, PayPeriodTracking)
import Domain.Absence (AbsenceContext)
import Domain.SchedulerConfig (SchedulerConfig)
import Domain.Pin (PinnedAssignment)
import Domain.PayPeriod (PayPeriodConfig)
import Domain.Hint (Hint)

-- | Opaque session identifier.
newtype SessionId = SessionId Int
    deriving (Eq, Ord, Show)

-- | Opaque authentication token (64-character hex string).
type Token = Text

-- | Metadata for a draft session.
data DraftInfo = DraftInfo
    { diId             :: !Int
    , diDateFrom       :: !Day
    , diDateTo         :: !Day
    , diCreatedAt      :: !Text
    , diLastValidatedAt :: !Text
    } deriving (Show, Eq)

-- | Metadata for a calendar history commit.
data CalendarCommit = CalendarCommit
    { ccId          :: !Int
    , ccCommittedAt :: !Text
    , ccDateFrom    :: !Day
    , ccDateTo      :: !Day
    , ccNote        :: !Text
    } deriving (Show)

-- | Structured audit log entry.
data AuditEntry = AuditEntry
    { aeId         :: !Int
    , aeTimestamp  :: !Text
    , aeUsername   :: !Text
    , aeCommand    :: !(Maybe Text)
    , aeEntityType :: !(Maybe Text)
    , aeOperation  :: !(Maybe Text)
    , aeEntityId   :: !(Maybe Int)
    , aeTargetId   :: !(Maybe Int)
    , aeDateFrom   :: !(Maybe Text)
    , aeDateTo     :: !(Maybe Text)
    , aeIsMutation :: !Bool
    , aeParams     :: !(Maybe Text)
    , aeSource     :: !Text
    } deriving (Show, Eq)

-- | Persisted hint session (hints + audit checkpoint).
data HintSessionRecord = HintSessionRecord
    { hsHints      :: ![Hint]
    , hsCheckpoint :: !Int        -- ^ audit_log.id of last-seen entry
    } deriving (Show, Eq)

-- | Record-of-functions abstracting over storage backend.
-- Each field is an IO action; swap the record to swap the backend
-- (e.g., SQLite -> PostgreSQL).
data Repository = Repository
    { -- ---------------------------------------------------------------
      -- Users
      -- ---------------------------------------------------------------
      repoCreateUser     :: Text -> Text -> Role -> WorkerId -> IO UserId
      -- ^ username, password hash, role, worker id
    , repoGetUser        :: UserId -> IO (Maybe User)
    , repoGetUserByName  :: Text -> IO (Maybe User)
    , repoUpdatePassword :: UserId -> Text -> IO ()
      -- ^ user id, new password hash
    , repoListUsers      :: IO [User]
    , repoDeleteUser     :: UserId -> IO ()

      -- ---------------------------------------------------------------
      -- Skills (entity CRUD)
      -- ---------------------------------------------------------------
    , repoCreateSkill    :: Text -> Text -> IO (Either String ())
      -- ^ name, description; Left if skill name already exists
    , repoDeleteSkill    :: SkillId -> IO ()
    , repoListSkills     :: IO [(SkillId, Skill)]
    , repoRenameSkill    :: SkillId -> Text -> IO ()
      -- ^ id, new name
    , repoListSkillImplications :: IO [(SkillId, SkillId)]
      -- ^ all (skill_id, implies_skill_id) pairs
    , repoRemoveSkillImplication :: SkillId -> SkillId -> IO ()
      -- ^ skill_id, implies_skill_id

      -- ---------------------------------------------------------------
      -- Stations (entity CRUD)
      -- ---------------------------------------------------------------
    , repoCreateStation  :: Text -> Int -> Int -> IO StationId
    , repoDeleteStation  :: StationId -> IO ()
    , repoListStations   :: IO [(StationId, Station)]
    , repoRenameStation  :: StationId -> Text -> IO ()

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
    , repoDeleteShift    :: Text -> IO ()
    , repoLoadShifts     :: IO [ShiftDef]

      -- ---------------------------------------------------------------
      -- Schedules
      -- ---------------------------------------------------------------
    , repoSaveSchedule   :: Text -> Schedule -> IO ()
      -- ^ Save a schedule under a name (overwrites if exists).
    , repoLoadSchedule   :: Text -> IO (Maybe Schedule)
    , repoListSchedules  :: IO [Text]
    , repoDeleteSchedule :: Text -> IO ()

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
    , repoLogCommandWithMeta :: Text -> Text -> Text -> CommandMeta -> IO ()
      -- ^ username, command string, source, pre-classified metadata
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
    , repoSaveCommit     :: Day -> Day -> Text -> Schedule -> IO Int
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
    , repoCalendarCommitsAfter :: Text -> IO [CalendarCommit]
      -- ^ List calendar commits with committed_at after the given timestamp
    , repoUpdateDraftValidatedAt :: Int -> IO ()
      -- ^ Update a draft's last_validated_at to current time

      -- ---------------------------------------------------------------
      -- Checkpoint (SQLite savepoints)
      -- ---------------------------------------------------------------
    , repoSavepoint      :: Text -> IO ()
      -- ^ Create a savepoint with the given name
    , repoRelease        :: Text -> IO ()
      -- ^ Release (commit) a savepoint
    , repoRollbackTo     :: Text -> IO ()
      -- ^ Rollback to a savepoint (savepoint remains active)

      -- ---------------------------------------------------------------
      -- Sessions
      -- ---------------------------------------------------------------
    , repoCreateSession     :: UserId -> IO (SessionId, Token)
      -- ^ Create a new active session for a user, returning session ID and auth token
    , repoGetActiveSession  :: UserId -> IO (Maybe SessionId)
      -- ^ Get the active session for a user, if any
    , repoTouchSession      :: SessionId -> IO ()
      -- ^ Update last_active_at to current time
    , repoCloseSession      :: SessionId -> IO ()
      -- ^ Mark a session as inactive
    , repoGetSessionByToken :: Token -> IO (Maybe (SessionId, UserId, UTCTime))
      -- ^ Look up a session by auth token; returns session ID, user ID, and last_active_at
    , repoGetSessionOwner :: SessionId -> IO (Maybe UserId)
      -- ^ Get the user ID that owns a session
    , repoGetIdleTimeoutMinutes :: IO Double
      -- ^ Get the session idle timeout in minutes (from scheduler_config)

      -- ---------------------------------------------------------------
      -- Hint sessions (persistent what-if)
      -- ---------------------------------------------------------------
    , repoSaveHintSession   :: SessionId -> Int -> [Hint] -> Int -> IO ()
      -- ^ session_id, draft_id, hints, checkpoint — upsert
    , repoLoadHintSession   :: SessionId -> Int -> IO (Maybe HintSessionRecord)
      -- ^ session_id, draft_id -> Maybe (hints, checkpoint)
    , repoDeleteHintSession :: SessionId -> Int -> IO ()
      -- ^ session_id, draft_id — delete (no-op if absent)

      -- ---------------------------------------------------------------
      -- Audit log (extended queries)
      -- ---------------------------------------------------------------
    , repoAuditSince        :: Int -> IO [AuditEntry]
      -- ^ Return mutating audit entries with id > checkpoint, ordered by id asc
    }
