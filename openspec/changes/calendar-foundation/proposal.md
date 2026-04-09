## Why

The scheduling system currently stores schedules as independent named snapshots with no relationship between them. Real-life restaurant scheduling requires a continuous calendar where accepted schedules accumulate over time, with the ability to overwrite date ranges (rescheduling) and review what was previously planned (audit trail). This is the foundation for monthly scheduling, concurrent drafts, and incremental rescheduling — all planned as subsequent changes.

## What Changes

- **New `calendar` table** replaces `schedules` + `assignments` as the authoritative store of accepted assignments. Assignments are keyed by date with no schedule-name grouping.
- **New `calendar_history` table** snapshots replaced assignments before each overwrite, recording the date range, timestamp, and optional note. Enables reconstructing the calendar state at any past point.
- **New CLI commands**: `calendar view <start> <end>`, `calendar view-by-worker <start> <end>`, `calendar view-by-station <start> <end>`, `calendar hours <start> <end>`, `calendar diagnose <start> <end>`, `calendar commit <name> <start> <end>` (bridge: saves a named schedule into the calendar with history).
- **BREAKING**: `schedule list` and named schedule storage are deprecated. Existing `schedule create` and `schedule view` commands continue to work but schedules are no longer the long-term storage model.
- **New service layer** for calendar operations: commit a schedule to a date range, load a calendar slice, query history.

## Capabilities

### New Capabilities
- `calendar-storage`: Single continuous calendar table for assignments, replacing named schedule storage. Includes calendar CRUD operations.
- `calendar-history`: History log that snapshots replaced assignments before each calendar overwrite, with date range, timestamp, and note. Enables audit trail queries.
- `calendar-cli`: CLI commands for viewing, querying, and committing to the calendar by date range.

### Modified Capabilities
- `compact-schedule-display`: View commands gain date-range variants for calendar display.

## Impact

- **Database schema**: New tables (`calendar`, `calendar_history`, `calendar_history_assignments`). Existing `schedules` and `assignments` tables retained for backward compatibility but deprecated.
- **Repo layer**: New functions in `Repo/SQLite.hs` for calendar operations.
- **Service layer**: New `Service/Calendar.hs` module.
- **CLI**: New command group `calendar` in `CLI/Commands.hs` and `CLI/App.hs`. Existing `schedule` commands unchanged.
- **Display**: `CLI/Display.hs` gains date-range-aware rendering (reuses existing table formatting).
- **Domain types**: No changes. `Schedule` (as `Set Assignment`) is the domain type used by both old and new storage.
