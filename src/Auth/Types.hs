module Auth.Types
    ( UserId(..)
    , Username(..)
    , Role(..)
    , User(..)
    ) where

import Data.Text (Text)
import Domain.Types (WorkerId)

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

-- | A system user. Every user is a worker; admin is just elevated privilege.
data User = User
    { userId       :: !UserId
    , userName     :: !Username
    , userPassHash :: !Text
    , userRole     :: !Role
    , userWorkerId :: !WorkerId     -- every user IS a worker
    } deriving (Eq, Show)
