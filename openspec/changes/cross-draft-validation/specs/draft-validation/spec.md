## ADDED Requirements

### Requirement: Detect stale draft on open
When a user opens a draft, the system SHALL check whether any calendar commits have a timestamp after the draft's last-validated timestamp. If so, the draft is considered stale and SHALL be re-validated before display.

#### Scenario: Draft is stale due to calendar change
- **WHEN** a draft was created at 10:00 and a calendar commit occurred at 11:00
- **THEN** the system detects the draft as stale and triggers re-validation

#### Scenario: Draft is not stale
- **WHEN** a draft was created at 11:00 and the most recent calendar commit was at 10:00
- **THEN** the system skips re-validation and opens the draft normally

#### Scenario: No calendar commits exist
- **WHEN** a draft is opened and no calendar commits exist at all
- **THEN** the system skips re-validation and opens the draft normally

#### Scenario: Draft already validated against latest calendar
- **WHEN** a draft was validated at 12:00 and the most recent calendar commit was at 11:00
- **THEN** the system skips re-validation (uses last-validated timestamp, not creation time)

### Requirement: Load calendar look-back context for validation
When re-validating a draft, the system SHALL load a calendar look-back window of at least 7 days immediately before the draft's start date. This look-back SHALL be used to populate context needed for cross-boundary constraint checks (alternating weekends, rest periods, consecutive hours).

#### Scenario: Look-back populates previous weekend workers
- **WHEN** the calendar shows Marco worked Saturday Apr 26 and Sunday Apr 27
- **AND** a May draft is being validated
- **THEN** Marco is included in the previous-weekend-workers set for validation

#### Scenario: Look-back populates previous day assignments for rest period
- **WHEN** the calendar shows Lucia worked until 22:00 on Apr 30
- **AND** a May 1-31 draft is being validated
- **THEN** Lucia's Apr 30 assignments are available for rest-period checks on May 1

#### Scenario: Empty look-back window
- **WHEN** the calendar has no assignments in the 7 days before the draft's start date
- **THEN** the previous-weekend-workers set is empty and no cross-boundary rest period violations are detected

### Requirement: Re-validate all draft assignments against hard constraints
When a draft is stale, the system SHALL check every assignment in the draft against the following hard constraints using the current calendar look-back context: skill qualification, absence conflicts, alternating weekends, weekly hour limits, daily hour limits, rest periods, consecutive hours, and avoid-pairing.

#### Scenario: Alternating weekend violation detected
- **WHEN** Marco worked the Apr 26-27 weekend (per calendar) and the draft assigns him to May 3 grill and May 4 grill
- **THEN** both May 3 and May 4 assignments are flagged as violating the alternating weekends constraint

#### Scenario: Skill qualification violation detected
- **WHEN** a worker's skill qualifications have changed (e.g., removed from grill skill) and the draft assigns them to grill
- **THEN** the grill assignments are flagged as violating skill qualification

#### Scenario: Absence conflict detected
- **WHEN** a new absence was approved for a worker covering a date in the draft
- **THEN** all assignments for that worker on that date are flagged as violating absence conflicts

#### Scenario: Rest period violation detected
- **WHEN** Lucia worked until 22:00 Apr 30 (per calendar) and the draft assigns her at 06:00 May 1 (8h gap, less than minimum rest)
- **THEN** the May 1 06:00 assignment is flagged as violating the rest period constraint

#### Scenario: Avoid-pairing violation detected
- **WHEN** two workers who should avoid each other are assigned to the same slot in the draft
- **THEN** one of the assignments is flagged as violating the avoid-pairing constraint

#### Scenario: No violations found
- **WHEN** all draft assignments still satisfy all hard constraints against the current calendar
- **THEN** no assignments are flagged and the draft opens normally with no validation messages

### Requirement: Auto-remove assignments that violate hard constraints
The system SHALL automatically remove all assignments that violate hard constraints from the draft and save the updated draft.

#### Scenario: Violating assignments are removed from draft
- **WHEN** 3 assignments are flagged as violating hard constraints
- **THEN** all 3 assignments are removed from the draft
- **AND** the updated draft is saved

#### Scenario: Non-violating assignments are preserved
- **WHEN** a draft has 100 assignments and 3 violate hard constraints
- **THEN** the 97 non-violating assignments remain in the draft unchanged

### Requirement: Report removed assignments with reasons
The system SHALL display a report of all removed assignments to the user, grouped by worker, with each removal showing the specific constraint violated and contextual details explaining why.

#### Scenario: Report format for alternating weekend violation
- **WHEN** Marco's May 3 grill and May 4 grill assignments are removed due to alternating weekends
- **THEN** the report shows Marco's name, the removed assignments, the constraint name "alternating weekends", and context "worked Apr 26-27 in calendar"

#### Scenario: Report format for rest period violation
- **WHEN** Lucia's May 1 06:00 grill assignment is removed due to rest period
- **THEN** the report shows Lucia's name, the removed assignment, the constraint name "rest period violation", and context about the insufficient gap

#### Scenario: Report includes summary counts
- **WHEN** 3 assignments are removed from the draft
- **THEN** the report header shows the draft name, that it was validated against an updated calendar, and the total count of removed assignments

#### Scenario: No report when no violations
- **WHEN** no assignments violate hard constraints
- **THEN** no validation report is displayed

### Requirement: Suggest diagnose after removals
After reporting removed assignments, the system SHALL suggest that the user run `diagnose` to identify unfilled positions and get suggestions for filling the gaps.

#### Scenario: Diagnose suggestion shown after removals
- **WHEN** assignments have been removed from the draft during validation
- **THEN** the system displays "Run 'diagnose' to see how to fill the gaps." after the violation report

#### Scenario: No diagnose suggestion when no removals
- **WHEN** no assignments were removed during validation
- **THEN** no diagnose suggestion is displayed

### Requirement: Update last-validated timestamp after validation
After a successful validation pass (whether or not violations were found), the system SHALL update the draft's last-validated timestamp to the current time. This prevents redundant re-validation on subsequent opens if the calendar has not changed again.

#### Scenario: Timestamp updated after validation with removals
- **WHEN** a draft is validated and 3 assignments are removed
- **THEN** the draft's last-validated timestamp is updated to the current time

#### Scenario: Timestamp updated after clean validation
- **WHEN** a draft is validated and no violations are found
- **THEN** the draft's last-validated timestamp is updated to the current time

#### Scenario: Re-opening does not re-validate if calendar unchanged
- **WHEN** a draft was validated at 12:00, the user closes and re-opens it at 12:05, and no calendar commits occurred after 12:00
- **THEN** re-validation is skipped
