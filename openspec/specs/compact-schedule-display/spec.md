## MODIFIED Requirements

### Requirement: Compact schedule view command
The system SHALL provide a `schedule view-compact <name>` command that displays the schedule in a table format fitting within 100 character columns. The existing `schedule view` command SHALL remain unchanged. Additionally, `calendar view-compact <start-date> <end-date>` SHALL display a calendar slice in the same compact format.

#### Scenario: View compact schedule
- **WHEN** user types `schedule view-compact april`
- **THEN** system displays the schedule in a compact table that does not exceed 100 characters per line

#### Scenario: Compact view of nonexistent schedule
- **WHEN** user types `schedule view-compact nosuch`
- **THEN** system displays "Schedule not found."

#### Scenario: Compact view of calendar slice
- **WHEN** user types `calendar view-compact 2026-04-06 2026-04-12`
- **THEN** system displays the calendar slice in the same compact format used by `schedule view-compact`
