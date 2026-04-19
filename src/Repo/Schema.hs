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
      \  skill_id INTEGER NOT NULL REFERENCES skills(id),\
      \  implies_skill_id INTEGER NOT NULL REFERENCES skills(id),\
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
      \  skill_id INTEGER NOT NULL REFERENCES skills(id),\
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
      \  skill_id INTEGER NOT NULL REFERENCES skills(id),\
      \  PRIMARY KEY (worker_id, skill_id)\
      \)"

    , "CREATE TABLE IF NOT EXISTS worker_hours (\
      \  worker_id INTEGER PRIMARY KEY,\
      \  max_period_seconds INTEGER NOT NULL\
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
      \  skill_id INTEGER NOT NULL REFERENCES skills(id),\
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
      \  command TEXT,\
      \  entity_type TEXT,\
      \  operation TEXT,\
      \  entity_id INTEGER,\
      \  target_id INTEGER,\
      \  date_from TEXT,\
      \  date_to TEXT,\
      \  is_mutation INTEGER NOT NULL DEFAULT 1,\
      \  params TEXT,\
      \  source TEXT NOT NULL DEFAULT 'cli'\
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

      -- Worker employment status (decomposed properties)
    , "CREATE TABLE IF NOT EXISTS worker_employment (\
      \  worker_id INTEGER PRIMARY KEY,\
      \  overtime_model TEXT NOT NULL DEFAULT 'eligible' CHECK (overtime_model IN ('eligible', 'manual-only', 'exempt')),\
      \  pay_period_tracking TEXT NOT NULL DEFAULT 'standard' CHECK (pay_period_tracking IN ('standard', 'exempt')),\
      \  is_temp BOOLEAN NOT NULL DEFAULT 0\
      \)"

      -- Pay period configuration (restaurant-wide, single row)
    , "CREATE TABLE IF NOT EXISTS pay_period_config (\
      \  period_type TEXT NOT NULL,\
      \  anchor_date TEXT NOT NULL\
      \)"

      -- Sessions (server-side session lifecycle)
    , "CREATE TABLE IF NOT EXISTS sessions (\
      \  id INTEGER PRIMARY KEY AUTOINCREMENT,\
      \  user_id INTEGER NOT NULL,\
      \  token TEXT NOT NULL,\
      \  created_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  last_active_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  is_active INTEGER NOT NULL DEFAULT 1\
      \)"

      -- Hint sessions (persistent what-if sessions)
    , "CREATE TABLE IF NOT EXISTS hint_sessions (\
      \  session_id INTEGER NOT NULL,\
      \  draft_id INTEGER NOT NULL,\
      \  hints_json TEXT NOT NULL,\
      \  checkpoint INTEGER NOT NULL,\
      \  created_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  updated_at TEXT NOT NULL DEFAULT (datetime('now')),\
      \  PRIMARY KEY (session_id, draft_id)\
      \)"
    ]

-- | Idempotent migrations for schema evolution.
-- Each ALTER TABLE is wrapped in a catch so it succeeds even if the
-- column already exists (e.g., on a freshly created database).
migrations :: [Query]
migrations =
    [
    -- Session auth token
      "CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions (token)"
    -- Session idle timeout default
    , "INSERT OR IGNORE INTO scheduler_config (key, value) VALUES ('session_idle_timeout_minutes', 30)"
    ]

-- | Try to execute a statement, silently ignoring errors (for idempotent migrations).
tryExec :: Connection -> Query -> IO ()
tryExec conn q = execute_ conn q `catch` \(_ :: SomeException) -> return ()
