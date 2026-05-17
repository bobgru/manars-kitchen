{-# LANGUAGE OverloadedStrings #-}
-- | User-level operations: rename, safe-delete, force-delete.
--
-- A user becomes a worker by virtue of having
-- @users.worker_status \in {\'active\',\'inactive\'}@. This module knows
-- the user-level rules; worker-level rules (references, deactivate,
-- delete) live in "Service.Worker".
module Service.User
    ( renameUser
    , safeDeleteUser
    , forceDeleteUser
    ) where

import qualified Data.Text as T
import Data.Text (Text)

import Auth.Types (User(..), Username(..), UserId(..), userIsWorker)
import Repo.Types (Repository(..))

-- | Rename a user (and therefore their worker name, if they are one).
-- Returns @Left@ with a human-readable message on collision or not-found.
renameUser :: Repository -> Text -> Text -> IO (Either String ())
renameUser repo oldName newName
    | T.null newName = pure $ Left "New username cannot be empty."
    | oldName == newName = pure $ Left "Old and new names are the same."
    | otherwise = do
        mOld <- repoGetUserByName repo oldName
        case mOld of
            Nothing -> pure $ Left ("No user named '" ++ T.unpack oldName ++ "'.")
            Just oldUser -> do
                mNew <- repoGetUserByName repo newName
                case mNew of
                    Just _ -> pure $ Left
                        ("Username '" ++ T.unpack newName ++ "' is already taken.")
                    Nothing -> do
                        repoRenameUser repo (userId oldUser) newName
                        pure (Right ())

-- | Safe-delete a user. Refuses to delete a user who is a worker (status
-- 'active' or 'inactive'). The caller should run @worker delete@ or
-- @worker force-delete@ first, or use 'forceDeleteUser'.
safeDeleteUser :: Repository -> UserId -> IO (Either String ())
safeDeleteUser repo uid = do
    mUser <- repoGetUser repo uid
    case mUser of
        Nothing -> pure $ Left ("User #" ++ show uid ++ " not found.")
        Just u
            | userIsWorker u ->
                let Username uname = userName u
                in pure $ Left $
                    "User '" ++ T.unpack uname ++ "' is a worker. " ++
                    "Use 'worker delete " ++ T.unpack uname ++ "' first, " ++
                    "or 'user force-delete' to cascade."
            | otherwise -> do
                repoDeleteUser repo uid
                pure (Right ())

-- | Cascade-delete a user: clear all worker-keyed references (config and
-- schedule) for the user's WorkerId, then delete the user row.
forceDeleteUser :: Repository -> UserId -> IO ()
forceDeleteUser = repoForceDeleteUser
