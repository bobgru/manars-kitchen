## Why

The calendar-foundation change (Change 1) introduced a single continuous calendar as the authoritative store for accepted assignments, replacing named schedules. But there is no safe way to work on a schedule before committing it -- any generation or editing immediately affects the calendar. Real restaurant scheduling requires a staging area: the manager needs to generate and tweak next month's schedule while the current month is still in progress, without those in-progress changes appearing in the live calendar. This change introduces draft sessions -- user-specified date-range working copies that are seeded from the calendar and pins, edited freely, and then committed or discarded.

## What Changes

- **New `drafts` table** stores draft session metadata (draft_id, date_from, date_to, created_at). A draft represents a working copy for a specific date range.
- **New `draft_assignments` table** stores assignments within a draft, same shape as `calendar_assignments` but keyed by draft_id. These are the editable working copy.
- **Non-overlapping invariant**: two drafts cannot cover overlapping date ranges. Enforced on creation.
- **Draft seeding**: when a draft is created, it is seeded by expanding pins into the date range and loading the existing calendar slice. Pins win conflicts (pin assignments override calendar assignments for the same worker/station/slot).
- **`draft generate`**: runs the existing scheduler within the draft context. The scheduler receives the draft's slots and seed schedule -- it does not know about drafts. The result replaces the draft's assignments.
- **Checkpoints within drafts**: the existing SQLite savepoint mechanism works as-is within a draft session.
- **`draft commit`**: snapshots the old calendar slice (using Change 1's history mechanism), then overwrites the calendar with the draft's assignments. The draft is deleted after commit.
- **`draft discard`**: deletes the draft and its assignments without touching the calendar.
- **Shortcut commands**: `draft this-month` (freeze-line+1 through end of current month) and `draft next-month` (next full calendar month) for the common concurrent case.
- **Up to 2+ concurrent drafts**: commonly this-month + next-month, enforced by the non-overlapping invariant.

## Capabilities

### New Capabilities
- `draft-session`: Create, open, commit, and discard draft sessions with date ranges. Includes draft lifecycle management, non-overlapping enforcement, and all draft manipulation commands (list, view, generate, commit, discard).
- `draft-seeding`: Seed a new draft from the calendar and pins. Expands pins into the draft's date range, loads the calendar slice, and merges with pin precedence (pins override calendar for conflicting worker/station/slot).
- `draft-shortcuts`: Convenience commands `draft this-month` and `draft next-month` that compute date ranges relative to the current date and freeze line.

### Modified Capabilities
- None. The scheduler, calendar, and pin systems are unchanged. The draft system wraps around them.

## Impact

- **Database schema**: New tables (`drafts`, `draft_assignments`) in `Repo/Schema.hs`.
- **Repo layer**: New functions in `Repo/Types.hs` and `Repo/SQLite.hs` for draft CRUD and draft assignment operations.
- **Service layer**: New `Service/Draft.hs` module for draft lifecycle (create with seeding, commit with history, discard, generate within draft).
- **CLI**: New command group `draft` in `CLI/Commands.hs` and `CLI/App.hs` with subcommands: create, this-month, next-month, list, open, view, generate, commit, discard.
- **Domain types**: No changes. `Schedule` (`Set Assignment`) is used as the domain type within drafts, same as everywhere else.
- **Scheduler**: No changes. The draft system prepares the context (slots, seed schedule) and passes it to the existing `buildScheduleFrom`.
- **Calendar/History**: Used as-is. `draft commit` calls the existing `commitToCalendar` service function.

## Dependencies

- **calendar-foundation** (Change 1): Required. Draft commit uses the calendar table and history mechanism introduced there.
