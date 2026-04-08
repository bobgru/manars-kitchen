## ADDED Requirements

### Requirement: Compact schedule view command
The system SHALL provide a `schedule view-compact <name>` command that displays the schedule in a table format fitting within 100 character columns. The existing `schedule view` command SHALL remain unchanged.

#### Scenario: View compact schedule
- **WHEN** user types `schedule view-compact april`
- **THEN** system displays the schedule in a compact table that does not exceed 100 characters per line

#### Scenario: Compact view of nonexistent schedule
- **WHEN** user types `schedule view-compact nosuch`
- **THEN** system displays "Schedule not found."

### Requirement: Compact table uses abbreviated names
The compact display SHALL abbreviate worker names and station names to fit within the column width budget. Worker names SHALL be truncated to a length that keeps the table within 100 columns. If truncation would make two names identical, the system SHALL extend both until they are distinguishable.

#### Scenario: Worker names abbreviated
- **WHEN** schedule has workers "marco" and "maria"
- **THEN** compact display shows "marc" and "mari" (or similar distinguishable abbreviations)

#### Scenario: Unique short names
- **WHEN** schedule has workers "alice" and "bob"
- **THEN** compact display may show "ali" and "bob" (names already distinguishable at 3 chars)

### Requirement: Compact table uses abbreviated hour headers
The compact display SHALL use abbreviated hour column headers (e.g., "6" instead of " 6:00") to save horizontal space.

#### Scenario: Hour headers in compact mode
- **WHEN** compact schedule is displayed
- **THEN** hour columns are labeled with just the hour number (e.g., "6", "10", "14")

### Requirement: Compact table preserves structure
The compact display SHALL maintain the same row structure as the wide display: rows grouped by day, sub-rows by station. Closed slots SHALL still appear as blank cells. The "." placeholder for unfilled positions SHALL still be used.

#### Scenario: Same day/station structure
- **WHEN** compact schedule is displayed
- **THEN** days appear as row groups and stations as sub-rows within each day, same as the wide view
