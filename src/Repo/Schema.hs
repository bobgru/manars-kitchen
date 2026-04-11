{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Repo.Schema
    ( initSchema
    ) where

import Control.Exception (catch, SomeException)
import Database.SQLite.Simple (Connection, Query, execute_)

-- | Create all tables if they don't already exist, then apply migrations.
initSchema :: Connection -> IO ()
initSchema conn = do
    mapM_ (execute_ conn) statements
    mapM_ (tryExec conn) migrations

statements :: [Query]
statements =
    [ -- Users
      "CREATE TABLE IF NOT EXISTS users (\
      \  id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  username TEXT NOT NULL UNIQUE,\
      \  password_hash TEXT NOT NULL,\
      \  role TEXT NOT NULL CHECK (role IN ('admin', 'normal')),\
      \  worker_id INTEGER NOT NULL\
      \)"

      -- Skills metadata
    , "CREATE TABLE IF NOT EXISTS skills (\
      \  id INTEGER PRIMARY KEY,\
      \  name TEXT NOT NULL,\
      \  description TEXT NOT NULL DEFAULT ''\
      \)"

    , "CREATE TABLE IF NOT EXISTS skill_implications (\
      \  skill_id INTEGER NOT NULL,\
      \  implies_skill_id INTEGER NOT NULL,\
      \  PRIMARY KEY (skill_id, implies_skill_id)\
      \)"

      -- Stations
    , "CREATE TABLE IF NOT EXISTS stations (\
      \  id INTEGER PRIMARY KEY,\
      \  name TEXT NOT NULL DEFAULT '',\
      \  min_staff INTEGER NOT NULL DEFAULT 1,\
      \  max_staff INTEGER NOT NULL DEFAULT 1\
      \)"

    , "CREATE TABLE IF NOT EXISTS station_required_skills (\
      \  station_id INTEGER NOT NULL,\
      \  skill_id INTEGER NOT NULL,\
      \  PRIMARY KEY (station_id, skill_id)\
      \)"

    , "CREATE TABLE IF NOT EXISTS station_open_hours (\
      \  station_id INTEGER NOT NULL,\
      \  day_of_week TEXT NOT NULL,\
      \  hour INTEGER NOT NULL,\
      \  PRIMARY KEY (station_id, day_of_week, hour)\
      \)"

    , "CREATE TABLE IF NOT EXISTS station_multi_hours (\
      \  station_id INTEGER NOT NULL,\
      \  day_of_week TEXT NOT NULL,\
      \  hour INTEGER NOT NULL,\
      \  PRIMARY KEY (station_id, day_of_week, hour)\
      \)"

      -- Workers
    , "CREATE TABLE IF NOT EXISTS worker_skills (\
      \  worker_id INTEGER NOT NULL,\
      \  skill_id INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, skill_id)\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_hours (\
      \  worker_id INTEGER PRIMARY KEY,\
      \  max_weekly_seconds INTEGER NOT NULL\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_overtime_optin (\
      \  worker_id INTEGER PRIMARY KEY\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_station_prefs (\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  rank INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, rank)\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_prefers_variety (\
      \  worker_id INTEGER PRIMARY KEY\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_shift_prefs (\
      \  worker_id INTEGER NOT NULL,\
      \  shift_name TEXT NOT NULL,\
      \  rank INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, rank)\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_weekend_only (\
      \  worker_id INTEGER PRIMARY KEY\
      \)"

      -- Absences
    , "CREATE TABLE IF NOT EXISTS absence_types (\
      \  id INTEGER PRIMARY KEY,\
      \  name TEXT NOT NULL,\
      \  yearly_limit INTEGER NOT NULL DEFAULT 0\
      \)"

    , "CREATE TABLE IF NOT EXISTS absence_requests (\
      \  id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  worker_id INTEGER NOT NULL,\
      \  type_id INTEGER NOT NULL,\
      \  start_day TEXT NOT NULL,\
      \  end_day TEXT NOT NULL,\
      \  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected'))\
      \)"

    , "CREATE TABLE IF NOT EXISTS yearly_allowances (\
      \  worker_id INTEGER NOT NULL,\
      \  type_id INTEGER NOT NULL,\
      \  days INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, type_id)\
      \)"

      -- Shifts
    , "CREATE TABLE IF NOT EXISTS shifts (\
      \  name TEXT PRIMARY KEY,\
      \  start_hour INTEGER NOT NULL,\
      \  end_hour INTEGER NOT NULL\
      \)"

      -- Schedules
    , "CREATE TABLE IF NOT EXISTS schedules (\
      \  name TEXT PRIMARY KEY,\
      \  created_at TEXT NOT NULL DEFAULT (datetime('now'))\
      \)"

    , "CREATE TABLE IF NOT EXISTS assignments (\
      \  schedule_name TEXT NOT NULL,\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  slot_date TEXT NOT NULL,\
      \  slot_start TEXT NOT NULL,\
      \  slot_duration_seconds INTEGER NOT NULL,\
      \  PRIMARY KEY (schedule_name, worker_id, station_id, slot_date, slot_start)\
      \)"

      -- Scheduler config (key-value store for scoring weights / rule thresholds)
    , "CREATE TABLE IF NOT EXISTS scheduler_config (\
      \  key TEXT PRIMARY KEY,\
      \  value REAL NOT NULL\
      \)"

      -- Worker seniority levels (controls max concurrent station assignments)
    , "CREATE TABLE IF NOT EXISTS worker_seniority (\
      \  worker_id INTEGER PRIMARY KEY,\
      \  level INTEGER NOT NULL\
      \)"

      -- Worker pairing (avoid / prefer)
    , "CREATE TABLE IF NOT EXISTS worker_avoid_pairing (\
      \  worker_id INTEGER NOT NULL,\
      \  other_id INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, other_id)\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_prefer_pairing (\
      \  worker_id INTEGER NOT NULL,\
      \  other_id INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, other_id)\
      \)"

      -- Worker cross-training goals
    , "CREATE TABLE IF NOT EXISTS worker_cross_training (\
      \  worker_id INTEGER NOT NULL,\
      \  skill_id INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, skill_id)\
      \)"

      -- Pinned assignments (recurring weekly)
    , "CREATE TABLE IF NOT EXISTS pinned_assignments (\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  day_of_week TEXT NOT NULL,\
      \  shift_name TEXT,\
      \  hour INTEGER NOT NULL DEFAULT -1,\
      \  PRIMARY KEY (worker_id, station_id, day_of_week, shift_name, hour)\
      \)"

      -- Audit log
    , "CREATE TABLE IF NOT EXISTS audit_log (\
      \  id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  timestamp TEXT NOT NULL DEFAULT (datetime('now')),\
      \  username TEXT NOT NULL,\
      \  command TEXT NOT NULL\
      \)"

      -- Calendar assignments (continuous calendar, no schedule name)
    , "CREATE TABLE IF NOT EXISTS calendar_assignments (\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  slot_date TEXT NOT NULL,\
      \  slot_start TEXT NOT NULL,\
      \  slot_duration_seconds INTEGER NOT NULL,\
      \  PRIMARY KEY (worker_id, station_id, slot_date, slot_start)\
      \)"

      -- Calendar commits (history metadata)
    , "CREATE TABLE IF NOT EXISTS calendar_commits (\
      \  id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  committed_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  date_from TEXT NOT NULL,\
      \  date_to TEXT NOT NULL,\
      \  note TEXT NOT NULL DEFAULT ''\
      \)"

      -- Calendar commit assignments (snapshot of replaced assignments)
    , "CREATE TABLE IF NOT EXISTS calendar_commit_assignments (\
      \  commit_id INTEGER NOT NULL,\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  slot_date TEXT NOT NULL,\
      \  slot_start TEXT NOT NULL,\
      \  slot_duration_seconds INTEGER NOT NULL,\
      \  PRIMARY KEY (commit_id, worker_id, station_id, slot_date, slot_start)\
      \)"

      -- Draft sessions (staging area for schedule work)
    , "CREATE TABLE IF NOT EXISTS drafts (\
      \  draft_id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  date_from TEXT NOT NULL,\
      \  date_to TEXT NOT NULL,\
      \  created_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  last_validated_at TEXT NOT NULL DEFAULT (datetime('now'))\
      \)"

      -- Draft assignments (working copy, same shape as calendar_assignments + draft_id)
    , "CREATE TABLE IF NOT EXISTS draft_assignments (\
      \  draft_id INTEGER NOT NULL,\
      \  worker_id INTEGER NOT NULL,\
      \  station_id INTEGER NOT NULL,\
      \  slot_date TEXT NOT NULL,\
      \  slot_start TEXT NOT NULL,\
      \  slot_duration_seconds INTEGER NOT NULL,\
      \  PRIMARY KEY (draft_id, worker_id, station_id, slot_date, slot_start)\
      \)"
    ]

-- | Idempotent migrations for schema evolution.
-- Each ALTER TABLE is wrapped in a catch so it succeeds even if the
-- column already exists (e.g., on a freshly created database).
migrations :: [Query]
migrations =
    [ "ALTER TABLE drafts ADD COLUMN last_validated_at TEXT NOT NULL DEFAULT (datetime('now'))"
    ]

-- | Try to execute a statement, silently ignoring errors (for idempotent migrations).
tryExec :: Connection -> Query -> IO ()
tryExec conn q = execute_ conn q `catch` \(_ :: SomeException) -> return ()
