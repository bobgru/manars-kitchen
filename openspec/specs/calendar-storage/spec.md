## ADDED Requirements

### Requirement: Single calendar table for assignments
The system SHALL maintain a `calendar_assignments` table that stores assignments without schedule-name grouping. Each row SHALL represent one worker assigned to one station at one time slot. The primary key SHALL be `(worker_id, station_id, slot_date, slot_start)`.

#### Scenario: Save assignments to calendar
- **WHEN** a schedule is committed to the calendar for date range Apr 1-30
- **THEN** all assignments from that schedule are stored in `calendar_assignments`

#### Scenario: No duplicate assignments
- **WHEN** an assignment for the same worker, station, date, and start time already exists
- **THEN** the existing assignment is replaced (upsert semantics)

### Requirement: Calendar commit replaces entire date range
When committing a schedule to the calendar for a date range, the system SHALL first delete all existing calendar assignments within that date range (inclusive), then insert the new assignments. The date range represents the caller's complete claim over that period.

#### Scenario: Commit overwrites existing assignments
- **WHEN** calendar has assignments for Apr 1-30 and a new schedule is committed for Apr 15-30
- **THEN** all existing assignments for Apr 15-30 are removed and replaced with the new schedule's assignments
- **AND** assignments for Apr 1-14 are unchanged

#### Scenario: Commit to empty date range
- **WHEN** no calendar assignments exist for May 1-31 and a schedule is committed for that range
- **THEN** all assignments from the schedule are inserted with no deletions

#### Scenario: Commit with sparse assignments
- **WHEN** a schedule is committed for Apr 1-30 but contains no assignments on Apr 7 (closed day)
- **THEN** any existing Apr 7 assignments are still deleted (the date range is the claim, not the assignments)

### Requirement: Load calendar slice by date range
The system SHALL support loading all calendar assignments within a specified date range (inclusive) and returning them as a `Schedule` domain type.

#### Scenario: Load a week slice
- **WHEN** calendar contains assignments for all of April and a slice is requested for Apr 7-13
- **THEN** only assignments with slot_date between Apr 7 and Apr 13 (inclusive) are returned

#### Scenario: Load empty range
- **WHEN** a slice is requested for a date range with no assignments
- **THEN** an empty `Schedule` is returned

### Requirement: Repository interface extended for calendar
The `Repository` record SHALL include new fields for calendar operations: save (upsert by date range), load (by date range), and the history operations defined in the calendar-history capability.

#### Scenario: Repository has calendar fields
- **WHEN** a `Repository` is constructed
- **THEN** it includes `repoSaveCalendar`, `repoLoadCalendar`, and calendar history fields
