## ADDED Requirements

### Requirement: Freeze line defaults to yesterday
The system SHALL compute the freeze line as yesterday's date (one day before the current system date). Dates before the freeze line (exclusive) are considered frozen. The freeze line SHALL NOT be stored — it is always computed from the current date.

#### Scenario: Freeze line on a normal day
- **WHEN** today is 2026-04-08
- **THEN** the freeze line is 2026-04-07
- **AND** dates on or before 2026-04-07 are frozen
- **AND** dates on or after 2026-04-08 are not frozen

#### Scenario: Freeze line at start of month
- **WHEN** today is 2026-05-01
- **THEN** the freeze line is 2026-04-30
- **AND** all of April and earlier is frozen

### Requirement: Warning on draft creation touching frozen dates
When a draft is created with a date range that includes dates on or before the freeze line, and those dates have not been explicitly unfrozen, the system SHALL display a warning listing the frozen dates in the range and ask for confirmation before proceeding.

#### Scenario: Draft entirely in the future
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-08 to 2026-04-14
- **THEN** no freeze warning is displayed and the draft is created normally

#### Scenario: Draft entirely in the past
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-01 to 2026-04-05
- **THEN** the system displays a warning: "WARNING: This draft covers dates before the freeze line (2026-04-07)."
- **AND** the warning lists the frozen dates in the range
- **AND** the system asks "Proceed anyway? (y/N)"

#### Scenario: Draft spanning the freeze line
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-05 to 2026-04-12
- **THEN** the system displays a warning identifying 2026-04-05 through 2026-04-07 as frozen
- **AND** the system asks for confirmation

#### Scenario: User confirms draft with frozen dates
- **WHEN** the system warns about frozen dates and the user responds "y"
- **THEN** the draft is created

#### Scenario: User declines draft with frozen dates
- **WHEN** the system warns about frozen dates and the user responds "n" or presses Enter
- **THEN** the draft is NOT created and the system displays "Draft creation cancelled."

#### Scenario: Draft touching unfrozen dates passes without warning
- **WHEN** the freeze line is 2026-04-07 and dates 2026-04-01 to 2026-04-07 have been explicitly unfrozen
- **AND** a draft is created for 2026-04-01 to 2026-04-14
- **THEN** no freeze warning is displayed and the draft is created normally

### Requirement: Unfreeze single date
The system SHALL provide `calendar unfreeze <date>` to temporarily unfreeze a single date for the current session. The unfrozen date SHALL be added to the session's set of unfrozen ranges.

#### Scenario: Unfreeze a single past date
- **WHEN** today is 2026-04-08 and user types `calendar unfreeze 2026-04-01`
- **THEN** 2026-04-01 is temporarily unfrozen
- **AND** the system confirms: "Unfrozen: 2026-04-01 (session only, will refreeze on commit or restart)"

#### Scenario: Unfreeze a future date
- **WHEN** today is 2026-04-08 and user types `calendar unfreeze 2026-04-10`
- **THEN** the system displays "Date 2026-04-10 is not frozen (it is after the freeze line 2026-04-07)."

#### Scenario: Unfreeze with invalid date format
- **WHEN** user types `calendar unfreeze not-a-date`
- **THEN** the system displays "Invalid date format. Use YYYY-MM-DD."

### Requirement: Unfreeze date range
The system SHALL provide `calendar unfreeze <start> <end>` to temporarily unfreeze an inclusive date range for the current session. Only the portion of the range that falls on or before the freeze line SHALL be unfrozen.

#### Scenario: Unfreeze a past date range
- **WHEN** today is 2026-04-08 and user types `calendar unfreeze 2026-04-01 2026-04-05`
- **THEN** dates 2026-04-01 through 2026-04-05 are temporarily unfrozen
- **AND** the system confirms: "Unfrozen: 2026-04-01 to 2026-04-05 (session only)"

#### Scenario: Unfreeze a range spanning the freeze line
- **WHEN** today is 2026-04-08 and user types `calendar unfreeze 2026-04-05 2026-04-12`
- **THEN** only dates 2026-04-05 through 2026-04-07 are unfrozen (dates after the freeze line are already unfrozen)
- **AND** the system confirms: "Unfrozen: 2026-04-05 to 2026-04-07 (session only, dates after freeze line already unfrozen)"

#### Scenario: Unfreeze with start after end
- **WHEN** user types `calendar unfreeze 2026-04-10 2026-04-05`
- **THEN** the system displays "Invalid range: start date must be on or before end date."

### Requirement: Freeze status command
The system SHALL provide `calendar freeze-status` that displays the current freeze line date and any temporarily unfrozen ranges in the session.

#### Scenario: Freeze status with no unfreezes
- **WHEN** today is 2026-04-08 and no dates have been unfrozen
- **AND** user types `calendar freeze-status`
- **THEN** system displays:
  ```
  Freeze line: 2026-04-07 (yesterday)
  No temporary unfreezes active.
  ```

#### Scenario: Freeze status with active unfreezes
- **WHEN** today is 2026-04-08 and dates 2026-04-01 to 2026-04-03 have been unfrozen
- **AND** user types `calendar freeze-status`
- **THEN** system displays:
  ```
  Freeze line: 2026-04-07 (yesterday)
  Unfrozen ranges: 2026-04-01 to 2026-04-03
  ```

#### Scenario: Freeze status with multiple unfrozen ranges
- **WHEN** dates 2026-04-01 to 2026-04-03 and 2026-04-05 have been unfrozen separately
- **AND** user types `calendar freeze-status`
- **THEN** system lists all unfrozen ranges

### Requirement: Auto-refreeze on draft commit
After a draft is committed that included dates on or before the freeze line, the system SHALL clear ALL temporary unfreezes from the session and display a message confirming the refreeze.

#### Scenario: Commit draft with unfrozen historical dates
- **WHEN** dates 2026-04-01 to 2026-04-05 were unfrozen and a draft covering those dates is committed
- **THEN** all temporary unfreezes are cleared
- **AND** the system displays "Historical dates refrozen. All temporary unfreezes cleared."

#### Scenario: Commit draft with only future dates
- **WHEN** a draft covering only future dates is committed and no unfreezes are active
- **THEN** no refreeze message is displayed

#### Scenario: Commit clears unrelated unfreezes too
- **WHEN** dates 2026-04-01 to 2026-04-03 and 2026-03-20 to 2026-03-25 were unfrozen
- **AND** a draft covering only 2026-04-01 to 2026-04-10 is committed
- **THEN** ALL unfreezes are cleared (including the 2026-03-20 to 2026-03-25 range)

### Requirement: Calendar unfreeze and freeze-status in help
The `calendar unfreeze` and `calendar freeze-status` commands SHALL appear in the help system under the `calendar` command group.

#### Scenario: Help calendar shows freeze commands
- **WHEN** user types `help calendar`
- **THEN** output includes `calendar unfreeze` and `calendar freeze-status` with brief descriptions
