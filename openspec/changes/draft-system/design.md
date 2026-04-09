## Context

After Change 1 (calendar-foundation), the system has a continuous calendar table where accepted assignments accumulate, and a history mechanism that snapshots replaced assignments before each overwrite. However, there is no staging area -- the only way to work on a schedule is through the old `schedule create` flow (which saves to named schedules) or by committing directly to the calendar.

The scheduler (`Domain/Scheduler.hs`) already works on whatever slots and seed schedule it receives via `buildScheduleFrom`. It has no awareness of where those slots came from or where the result is stored. This means a draft system only needs to control what goes into and out of the scheduler -- no scheduler changes required.

Pins (`Domain/Pin.hs`) represent recurring weekly assignments (e.g., "Worker 3 always works the morning shift at Station 1 on Mondays"). They are expanded into concrete assignments for a given set of slots via `expandPins`. The current `Service/Schedule.hs` already seeds the scheduler with expanded pins. The draft system needs the same seeding logic, plus merging with existing calendar data.

The checkpoint system (`repoSavepoint`, `repoRelease`, `repoRollbackTo` in `Repo/Types.hs`) uses SQLite savepoints. Since draft assignments live in a regular SQLite table, savepoints work on them automatically -- no changes needed.

## Goals / Non-Goals

**Goals:**
- Provide a staging area (draft) for working on schedules before committing to the calendar
- Support concurrent drafts for non-overlapping date ranges (typical case: this-month + next-month)
- Seed drafts from calendar + pins with pin precedence
- Run the existing scheduler within a draft context
- Commit a draft to the calendar using the existing history mechanism
- Discard a draft without side effects
- Provide shortcut commands for the common this-month/next-month workflow

**Non-Goals:**
- Changes to the scheduler algorithm or domain types
- Collaborative editing (multiple users editing the same draft)
- Draft versioning or undo within a draft (checkpoints already handle this)
- Freeze line logic (Change 3)
- Validation or constraint checking on drafts (Change 4)
- Merging overlapping drafts

## Decisions

### Draft storage uses a separate table, not the calendar

Draft assignments are stored in a `draft_assignments` table with the same columns as `calendar_assignments` plus a `draft_id` foreign key. Each draft has its own isolated copy of assignments for its date range.

**Alternative considered:** Store draft assignments in `calendar_assignments` with a "draft" flag or namespace. Rejected because it would mix uncommitted work with the authoritative calendar, complicating every calendar query with draft-exclusion logic. A separate table provides clean isolation.

### Seeding merge strategy: pins override calendar

When a draft is created for a date range, the seeding process is:
1. Load existing `calendar_assignments` for the date range into a `Schedule`
2. Expand pins for the date range's slots using `expandPins`
3. Merge: union the two sets, but pin assignments win when there is a conflict on the same worker + slot (same worker, same date, same start time)

"Pins win" means: if a pin says Worker 3 is at Station 1 on Monday 9:00, and the calendar has Worker 3 at Station 2 on Monday 9:00, the draft starts with the pin's version. This reflects the intent that pins represent the manager's standing preferences.

**Alternative considered:** Calendar wins (pins are informational). Rejected because the whole point of pins is that they represent recurring intent that should be the default starting point.

**Alternative considered:** Conflict raises an error. Rejected because conflicts are normal (the calendar may have been generated before the pin was added) and the manager wants the draft to reflect current pin state.

### Non-overlapping date range enforcement

Two active drafts cannot cover overlapping date ranges. On `draft create`, the system checks all existing drafts and rejects creation if any date range overlap exists. This is checked with a simple SQL query: `SELECT 1 FROM drafts WHERE date_from <= ? AND date_to >= ?` (with the new draft's to/from).

**Why:** Overlapping drafts create ambiguity about which draft "owns" a date. If both drafts are committed, the second commit would overwrite the first. Rather than complex merge logic, we prevent the conflict at creation time.

**Implication:** The manager plans in non-overlapping chunks. The shortcut commands (`this-month`, `next-month`) naturally produce non-overlapping ranges.

### `draft generate` reuses the scheduler as-is

The `draft generate` command:
1. Loads the draft's current assignments as the seed schedule
2. Builds the slot list for the draft's date range
3. Loads all scheduler contexts (skills, workers, absences, config, shifts, pins)
4. Calls `buildScheduleFrom seed ctx` -- the exact same function used by `schedule create`
5. Saves the result back into `draft_assignments` (replacing existing)

The scheduler does not know it is operating within a draft. It receives slots and a seed and returns a schedule. The draft system is the orchestrator.

**Difference from `schedule create`:** `schedule create` saves to a named schedule. `draft generate` saves back into the draft. The scheduler call is identical.

### Draft commit delegates to calendar-foundation's commit mechanism

`draft commit` performs:
1. Load draft metadata (date range)
2. Load draft assignments as a `Schedule`
3. Call `commitToCalendar repo dateFrom dateTo note schedule` -- the same service function from Change 1
4. Delete the draft and its assignments

This means draft commit gets history snapshots for free. The pre-existing calendar assignments in the draft's date range are snapshotted before overwrite, exactly as if the commit came from any other source.

### Service layer in Service/Draft.hs

New module `Service/Draft.hs` with:
- `createDraft :: Repository -> Day -> Day -> IO DraftId` -- check non-overlap, seed from calendar + pins, return draft id
- `listDrafts :: Repository -> IO [Draft]` -- list active drafts
- `loadDraft :: Repository -> DraftId -> IO (Maybe DraftInfo)` -- load draft metadata and assignments
- `generateDraft :: Repository -> DraftId -> Set WorkerId -> IO ScheduleResult` -- run scheduler within draft
- `commitDraft :: Repository -> DraftId -> String -> IO ()` -- commit to calendar with history, delete draft
- `discardDraft :: Repository -> DraftId -> IO ()` -- delete draft and assignments

### Repo.Types gains draft operations

New fields added to the `Repository` record:
- `repoCreateDraft :: Day -> Day -> IO Int` -- insert draft, return draft_id
- `repoDeleteDraft :: Int -> IO ()` -- delete draft and its assignments
- `repoListDrafts :: IO [(Int, Day, Day, String)]` -- list drafts (id, from, to, created_at)
- `repoGetDraft :: Int -> IO (Maybe (Day, Day, String))` -- get draft metadata
- `repoCheckDraftOverlap :: Day -> Day -> IO Bool` -- check if date range overlaps existing draft
- `repoSaveDraftAssignments :: Int -> Schedule -> IO ()` -- save assignments for a draft (replace existing)
- `repoLoadDraftAssignments :: Int -> IO Schedule` -- load assignments for a draft
- `repoLoadDraftSlots :: Int -> IO [Slot]` -- load the slot list for a draft's date range

### CLI adds a `draft` command group

New commands:
- `draft create <start-date> <end-date>` -- create a draft for the date range
- `draft this-month` -- create a draft for freeze-line+1 through end of current month
- `draft next-month` -- create a draft for next calendar month
- `draft list` -- list active drafts
- `draft open <draft-id>` -- display draft info and assignments
- `draft view [draft-id]` -- view draft assignments in the current/specified draft
- `draft generate [draft-id]` -- run the scheduler within a draft
- `draft commit [draft-id] [note]` -- commit draft to calendar
- `draft discard [draft-id]` -- discard draft without affecting calendar
- `draft view-compact [draft-id]` -- compact view of draft assignments
- `draft hours [draft-id]` -- hour summaries for draft
- `draft diagnose [draft-id]` -- coverage analysis for draft

The view/generate/commit/discard commands accept an optional draft-id. When omitted, they operate on the sole active draft (error if 0 or 2+).

### Shortcut date range computation

- `draft this-month`: date_from = today + 1 day (simplification of freeze-line; actual freeze line is a Change 3 concern), date_to = last day of current month. If today is the last day of the month, this is invalid (empty range).
- `draft next-month`: date_from = first day of next month, date_to = last day of next month.

These are pure date computations with no special logic. The freeze line integration (Change 3) will refine `this-month` to use the actual freeze line instead of today+1.

## Risks / Trade-offs

**[Risk] Draft left uncommitted indefinitely** -- A draft could be created and forgotten, blocking that date range from future drafts.
-> Mitigation: `draft list` shows all active drafts with creation timestamps. The manager can discard stale drafts. No automatic expiration (the restaurant has one manager; this is not a multi-tenant system).

**[Risk] Calendar changes between draft creation and commit** -- If someone commits to the calendar for dates overlapping a draft's range after the draft was created, the draft's seed is stale.
-> Mitigation: This is acceptable. The draft commit will overwrite the calendar slice, which is the correct behavior (the draft is the manager's intended state). The overwritten assignments are captured in history. In practice, only one person manages the schedule.

**[Risk] Non-overlapping constraint is too strict** -- A manager might want to reschedule a single week that falls within a month-long draft.
-> Mitigation: The manager should use checkpoints within the existing draft rather than creating a sub-draft. The non-overlapping constraint keeps the model simple. If a real need emerges, it can be relaxed later.

**[Risk] Seeding logic duplicates parts of Service/Schedule.hs** -- The pin expansion and scheduler invocation pattern is similar to `createSchedule`.
-> Mitigation: Extract shared logic into a helper if duplication becomes problematic. For now, the two paths are different enough (one saves to a named schedule, one saves to a draft) that slight duplication is acceptable.
