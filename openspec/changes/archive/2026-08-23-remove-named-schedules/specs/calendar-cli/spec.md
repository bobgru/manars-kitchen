## REMOVED Requirements

### Requirement: Calendar commit command
**Reason**: `calendar commit` read its assignments from a named schedule, which no
longer exists. `draft commit <id> [note]` performs the identical calendar write
(the same `Service.Calendar.commitToCalendar` call) and additionally deletes the
committed draft, clears what-if sessions and re-applies the freeze line.

**Migration**: Replace `calendar commit <name> <start> <end> [note]` with
`draft create <start> <end>`, `draft generate <id>`, `draft commit <id> [note]`.

## MODIFIED Requirements

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
