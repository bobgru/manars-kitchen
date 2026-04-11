## Context

The system currently stores schedules as named snapshots: each `schedule create week1 2026-04-06` produces a row in `schedules` (keyed by name) with child rows in `assignments` (keyed by `schedule_name + worker + station + slot`). Schedules are independent — there is no concept of accumulation, overwriting, or history.

The domain type `Schedule` (a `Set Assignment` in `Domain/Types.hs`) has no identity or date boundary — it's just a set of assignments. The scheduler operates on whatever slots it receives. This means the domain layer already supports the calendar concept; the gap is in the storage and CLI layers.

The repository abstraction (`Repo/Types.hs`) uses a record-of-functions pattern, making it straightforward to add new operations without breaking existing ones.

## Goals / Non-Goals

**Goals:**
- Introduce a single authoritative calendar table where accepted assignments accumulate
- Provide a history mechanism that snapshots replaced assignments before each overwrite
- Add CLI commands for viewing and committing to the calendar by date range
- Preserve existing `schedule` commands during transition (no forced migration)

**Non-Goals:**
- Draft system (Change 2 — depends on calendar existing first)
- Freeze line or validation logic (Changes 3-4)
- Changes to the scheduler algorithm or domain types
- Data migration of existing named schedules into the calendar (manual via `calendar commit`)
- Month-scale scheduling or pay periods

## Decisions

### Calendar table mirrors the assignments table without schedule_name

The new `calendar_assignments` table has the same columns as `assignments` minus `schedule_name`. The primary key becomes `(worker_id, station_id, slot_date, slot_start)` — the natural key for "one worker at one station at one time."

**Alternative considered:** Reuse the `assignments` table with a reserved schedule name (e.g., `__calendar__`). Rejected because it conflates two concepts and makes the PK awkward. A clean table is simpler.

### History uses a two-table pattern: commits + snapshot assignments

A `calendar_commits` table records each overwrite (id, timestamp, date range, note). A `calendar_commit_assignments` table stores the assignments that were replaced, keyed by commit id. This allows efficient queries like "what was replaced on commit #5" without scanning blobs.

**Alternative considered:** Store replaced assignments as a JSON blob in the commit row. Rejected because it prevents SQL-level queries over historical assignments and is harder to work with in Haskell (requires JSON round-trip).

### Calendar operations go through a new service module

New `Service/Calendar.hs` module with:
- `commitToCalendar :: Repository -> Day -> Day -> String -> Schedule -> IO ()` — snapshot existing assignments in range, then overwrite
- `loadCalendarSlice :: Repository -> Day -> Day -> IO Schedule` — load assignments for a date range
- `listCommits :: Repository -> IO [CalendarCommit]` — list history

This keeps the repository layer thin (raw CRUD) and puts the snapshot-then-overwrite logic in the service layer.

### Repo.Types gains calendar operations alongside existing schedule operations

New fields added to the `Repository` record:
- `repoSaveCalendar :: Day -> Day -> Schedule -> IO ()` — upsert assignments for date range (delete existing in range, insert new)
- `repoLoadCalendar :: Day -> Day -> IO Schedule` — load assignments by date range
- `repoSaveCommit :: Day -> Day -> String -> Schedule -> IO Int` — save a history commit with the old assignments, return commit id
- `repoListCommits :: IO [(Int, String, Day, Day, String)]` — list commits (id, timestamp, from, to, note)
- `repoLoadCommitAssignments :: Int -> IO Schedule` — load snapshot for a commit

Existing `repoSaveSchedule`, `repoLoadSchedule`, etc. are unchanged.

### CLI adds a `calendar` command group

New commands:
- `calendar view <start-date> <end-date>` — table view of calendar slice
- `calendar view-by-worker <start-date> <end-date>` — grouped by worker
- `calendar view-by-station <start-date> <end-date>` — grouped by station
- `calendar view-compact <start-date> <end-date>` — compact format
- `calendar hours <start-date> <end-date>` — hour summaries
- `calendar diagnose <start-date> <end-date>` — coverage analysis
- `calendar commit <schedule-name> <start-date> <end-date>` — commit a named schedule to the calendar
- `calendar history` — list commits
- `calendar history <commit-id>` — view a specific historical snapshot

The display functions in `CLI/Display.hs` already take a `Schedule` and render it. The calendar commands load a `Schedule` from the calendar table and pass it to the same renderers.

### Bridge workflow: commit named schedules into the calendar

The `calendar commit` command takes a named schedule and a date range, loads the schedule, and commits it to the calendar. This lets users adopt the calendar incrementally — generate schedules the old way, then commit them.

The date range is explicit rather than inferred from the schedule's assignments because a schedule might have sparse assignments and the user needs to declare what date range is being "claimed."

## Risks / Trade-offs

**[Risk] Two sources of truth during transition** — Both `assignments` (named schedules) and `calendar_assignments` exist. Users might forget to commit.
→ Mitigation: `calendar commit` is the bridge. Future Change 2 (drafts) will make this the default flow. Clear deprecation messaging on `schedule` commands.

**[Risk] History table grows unboundedly** — Every commit snapshots all replaced assignments.
→ Mitigation: For a restaurant with ~12 workers and monthly schedules, each commit is ~2000-5000 assignment rows. Years of history fit comfortably in SQLite. Can add pruning later if needed.

**[Risk] Date range semantics for commit** — If a user commits a schedule to Apr 1-30 but the schedule has no assignments on Apr 7 (closed day), does that wipe any existing Apr 7 assignments?
→ Decision: Yes. The date range is the "claim" — the commit replaces everything in that range. The caller is asserting "this is the complete truth for Apr 1-30." This is simpler and less error-prone than trying to infer gaps.
