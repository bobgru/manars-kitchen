## ADDED Requirements

### Requirement: Calendar view by date range
The system SHALL provide `calendar view <start-date> <end-date>` that displays the
calendar slice as a time-slot grid, using the same table format as `draft view`.

#### Scenario: View a week of calendar
- **WHEN** user types `calendar view 2026-04-06 2026-04-12`
- **THEN** system displays a time-slot grid for that date range using calendar assignments

#### Scenario: View empty date range
- **WHEN** user types `calendar view 2026-06-01 2026-06-07` and no assignments exist for those dates
- **THEN** system displays "No calendar assignments in this range."

### Requirement: Calendar view-by-worker
The system SHALL provide `calendar view-by-worker <start-date> <end-date>` that
displays calendar assignments grouped by worker, using the same format as the
draft and calendar by-worker renderer.

#### Scenario: View by worker
- **WHEN** user types `calendar view-by-worker 2026-04-06 2026-04-12`
- **THEN** system displays calendar assignments grouped by worker for that date range

### Requirement: Calendar view-by-station
The system SHALL provide `calendar view-by-station <start-date> <end-date>` that displays calendar assignments grouped by station.

#### Scenario: View by station
- **WHEN** user types `calendar view-by-station 2026-04-06 2026-04-12`
- **THEN** system displays calendar assignments grouped by station for that date range

### Requirement: Calendar view-compact
The system SHALL provide `calendar view-compact <start-date> <end-date>` that displays the calendar slice in the compact 100-column format.

#### Scenario: Compact view of calendar
- **WHEN** user types `calendar view-compact 2026-04-06 2026-04-12`
- **THEN** system displays the calendar slice in compact format

### Requirement: Calendar hours summary
The system SHALL provide `calendar hours <start-date> <end-date>` that displays per-worker hour summaries for the date range.

#### Scenario: Hours summary
- **WHEN** user types `calendar hours 2026-04-06 2026-04-12`
- **THEN** system displays per-worker hours for that date range

### Requirement: Calendar diagnose
The system SHALL provide `calendar diagnose <start-date> <end-date>` that runs coverage analysis on the calendar slice.

#### Scenario: Diagnose coverage
- **WHEN** user types `calendar diagnose 2026-04-06 2026-04-12`
- **THEN** system displays unfilled position analysis and suggestions for that date range

### Requirement: Calendar history commands
The system SHALL provide `calendar history` to list all commits and `calendar history <commit-id>` to view the snapshot of a specific commit.

#### Scenario: List history
- **WHEN** user types `calendar history`
- **THEN** system displays a list of commits with id, timestamp, date range, and note

#### Scenario: View specific commit
- **WHEN** user types `calendar history 2`
- **THEN** system displays the assignments that were replaced by commit #2

#### Scenario: View nonexistent commit
- **WHEN** user types `calendar history 999`
- **THEN** system displays "Commit not found: 999"

### Requirement: Calendar commands in help
The `calendar` command group SHALL appear in the two-level help system. `help` SHALL list the calendar group, and `help calendar` SHALL show all calendar subcommands.

#### Scenario: Help shows calendar group
- **WHEN** user types `help`
- **THEN** output includes `calendar` in the command group list

#### Scenario: Help calendar shows subcommands
- **WHEN** user types `help calendar`
- **THEN** output lists all calendar subcommands with brief descriptions
