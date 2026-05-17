{-# LANGUAGE OverloadedStrings #-}
-- | Test helper for seeding the @users@ table so worker-keyed tables
-- satisfy their @REFERENCES users(id)@ foreign keys.
--
-- After the @worker-foundation@ change, every @worker_*.worker_id@ and
-- @assignments.worker_id@ etc. is a FK to @users(id)@. Tests that insert
-- raw @WorkerId@ values (1, 2, 3, ...) need matching user rows or the
-- FK will fire.
module TestSeed
    ( seedTestUsers
    ) where

import qualified Data.Text as T
import Repo.Types (Repository(..))
import Auth.Types (Role(..))

-- | Insert @users@ rows for worker IDs @1..n@ so that worker-keyed FKs
-- resolve. Each user is created as a worker (status = 'active').
-- This is intended for tests that reference @WorkerId@ values directly.
seedTestUsers :: Repository -> Int -> IO ()
seedTestUsers repo n =
    mapM_ (\i -> do
        _ <- repoCreateUser repo (T.pack ("test-user-" ++ show i)) "" Normal False
        return ()
        ) [1..n]
