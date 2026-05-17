module Auth.Types
    ( UserId(..)
    , Username(..)
    , Role(..)
    , User(..)
    , userIdToWorkerId
    , workerIdToUserId
    , userIsWorker
    ) where

import Data.Text (Text)
import Data.Time (Day)
import Domain.Types (WorkerId(..), WorkerStatus(..))

-- | Terminal unit: a system user, identified by an opaque ID.
newtype UserId = UserId Int
    deriving (Eq, Ord, Show, Read)

-- | A unique login name.
newtype Username = Username Text
    deriving (Eq, Ord, Show, Read)

-- | Admin = manager (full CRUD on all entities).
-- Normal = worker (view schedule, request absences, update preferences).
data Role = Admin | Normal
    deriving (Eq, Ord, Show, Read, Enum, Bounded)

-- | A system user. A user may or may not be a worker (see 'userWorkerStatus').
-- When the user is a worker (status active or inactive), their 'WorkerId' is
-- the same integer as their 'UserId' (use 'userIdToWorkerId').
data User = User
    { userId            :: !UserId
    , userName          :: !Username
    , userPassHash      :: !Text
    , userRole          :: !Role
    , userWorkerStatus  :: !WorkerStatus
    , userDeactivatedAt :: !(Maybe Day)
    } deriving (Eq, Show)

-- | A worker's 'WorkerId' is the integer value of their 'UserId'.
-- This is only meaningful when the user is a worker (status /= 'WSNone').
userIdToWorkerId :: UserId -> WorkerId
userIdToWorkerId (UserId n) = WorkerId n

-- | The 'UserId' of the user behind a 'WorkerId'.
workerIdToUserId :: WorkerId -> UserId
workerIdToUserId (WorkerId n) = UserId n

-- | True iff the user's 'WorkerStatus' is 'WSActive' or 'WSInactive'.
userIsWorker :: User -> Bool
userIsWorker u = case userWorkerStatus u of
    WSNone     -> False
    WSActive   -> True
    WSInactive -> True
