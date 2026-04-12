## ADDED Requirements

### Requirement: Close station hint
The system SHALL provide `what-if close-station <station> <day> <hour>` that adds a CloseStation hint to the active hint session. The `<station>` argument SHALL accept a station ID or name. The `<day>` argument SHALL accept a date in YYYY-MM-DD format. The `<hour>` argument SHALL accept an integer hour (e.g., 9 for 9:00). After adding the hint, the system SHALL display a diff summary.

#### Scenario: Close a station at a specific slot
- **WHEN** user types `what-if close-station grill 2026-04-06 9`
- **THEN** system resolves "grill" to a station ID, adds a CloseStation hint for that station at the 9:00 slot on Apr 6, recomputes the schedule, and displays the diff (e.g., "1 assignment removed, 1 unfilled position added")

#### Scenario: Close station with invalid station name
- **WHEN** user types `what-if close-station nosuch 2026-04-06 9`
- **THEN** system displays "Unknown station: nosuch"

#### Scenario: Close station with invalid date
- **WHEN** user types `what-if close-station grill baddate 9`
- **THEN** system displays "Invalid date format. Use YYYY-MM-DD."

### Requirement: Pin assignment hint
The system SHALL provide `what-if pin <worker> <station> <day> <hour>` that adds a PinAssignment hint. All arguments SHALL accept names or IDs via existing entity resolution. After adding the hint, the system SHALL display a diff summary.

#### Scenario: Pin a worker to a station
- **WHEN** user types `what-if pin marco grill 2026-04-06 9`
- **THEN** system adds a PinAssignment hint forcing marco to grill at 9:00 on Apr 6, recomputes, and displays the diff

#### Scenario: Pin with dot substitution
- **WHEN** worker context is set to "marco" and station context is set to "grill"
- **AND** user types `what-if pin . . 2026-04-06 9`
- **THEN** system resolves dots to marco and grill, adds the PinAssignment hint

### Requirement: Add worker hint
The system SHALL provide `what-if add-worker <name> <skills...> [hours]` that adds an AddWorker hint with a temporary worker. The `<name>` argument SHALL be a display name for the temporary worker. The `<skills...>` arguments SHALL accept skill names or IDs. An optional final numeric argument SHALL set the weekly hour limit. After adding the hint, the system SHALL display a diff summary.

#### Scenario: Add a temp worker with skills
- **WHEN** user types `what-if add-worker temp-chef cooking 40`
- **THEN** system adds an AddWorker hint with skill "cooking" and 40-hour limit, recomputes, and displays the diff showing the temp worker's assignments

#### Scenario: Add a temp worker without hour limit
- **WHEN** user types `what-if add-worker temp-prep prep`
- **THEN** system adds an AddWorker hint with skill "prep" and no hour limit

#### Scenario: Add worker with unknown skill
- **WHEN** user types `what-if add-worker temp-chef nosuchskill`
- **THEN** system displays "Unknown skill: nosuchskill"

### Requirement: Waive overtime hint
The system SHALL provide `what-if waive-overtime <worker>` that adds a WaiveOvertime hint. The `<worker>` argument SHALL accept a name or ID. After adding the hint, the system SHALL display a diff summary.

#### Scenario: Waive overtime for a worker
- **WHEN** user types `what-if waive-overtime bob`
- **THEN** system adds a WaiveOvertime hint for bob, recomputes, and displays the diff (e.g., new assignments now possible due to overtime allowance)

### Requirement: Grant skill hint
The system SHALL provide `what-if grant-skill <worker> <skill>` that adds a GrantSkill hint. Both arguments SHALL accept names or IDs. After adding the hint, the system SHALL display a diff summary.

#### Scenario: Grant a skill hypothetically
- **WHEN** user types `what-if grant-skill carol cooking`
- **THEN** system adds a GrantSkill hint, recomputes, and displays the diff (e.g., carol now assigned to stations requiring cooking)

#### Scenario: Grant skill with dot substitution
- **WHEN** worker context is "carol" and skill context is "cooking"
- **AND** user types `what-if grant-skill . .`
- **THEN** system resolves dots and adds the GrantSkill hint

### Requirement: Override preferences hint
The system SHALL provide `what-if override-prefs <worker> <stations...>` that adds an OverridePreference hint. The `<worker>` argument SHALL accept a name or ID. The `<stations...>` arguments SHALL accept station names or IDs. After adding the hint, the system SHALL display a diff summary.

#### Scenario: Override station preferences
- **WHEN** user types `what-if override-prefs marco grill prep-table`
- **THEN** system adds an OverridePreference hint with the specified stations, recomputes, and displays the diff

### Requirement: Revert last hint
The system SHALL provide `what-if revert` that removes the most recent hint from the session, recomputes the schedule, and displays the diff. If no hints are active, the system SHALL display "No hints to revert."

#### Scenario: Revert with active hints
- **WHEN** hint session has 2 hints and user types `what-if revert`
- **THEN** system removes the last hint, recomputes, displays the diff, and reports "Reverted hint 2. 1 hint remaining."

#### Scenario: Revert with no hints
- **WHEN** hint session has 0 hints and user types `what-if revert`
- **THEN** system displays "No hints to revert."

### Requirement: Revert all hints
The system SHALL provide `what-if revert-all` that removes all hints from the session, recomputes the schedule, and displays the diff from the fully-hinted state to the original. If no hints are active, the system SHALL display "No hints to revert."

#### Scenario: Revert all hints
- **WHEN** hint session has 3 hints and user types `what-if revert-all`
- **THEN** system clears all hints, recomputes, displays the diff, and reports "Reverted all 3 hints."

### Requirement: List active hints
The system SHALL provide `what-if list` that displays all active hints in order, numbered starting from 1. Each hint SHALL be displayed in human-readable form using entity names (not just IDs). If no hints are active, the system SHALL display "No active hints."

#### Scenario: List with active hints
- **WHEN** hint session has 2 hints: GrantSkill for carol/cooking and CloseStation for grill/Monday 9:00
- **AND** user types `what-if list`
- **THEN** system displays:
  ```
  Active hints:
    1. Grant skill: carol -> cooking
    2. Close station: grill on 2026-04-06 at 9:00
  ```

#### Scenario: List with no hints
- **WHEN** hint session has 0 hints and user types `what-if list`
- **THEN** system displays "No active hints."

### Requirement: Diff display after hint operations
After each hint add or revert operation, the system SHALL display a summary of schedule changes including: assignments added (count and details), assignments removed (count and details), unfilled positions gained, and unfilled positions resolved. Entity names SHALL be used for readability. If nothing changed, the system SHALL display "No schedule changes."

#### Scenario: Hint causes assignment changes
- **WHEN** a CloseStation hint removes an assignment
- **THEN** system displays something like:
  ```
  - Removed: marco @ grill on Mon 9:00
  + Unfilled: grill on Mon 9:00
  ```

#### Scenario: Hint resolves unfilled position
- **WHEN** a GrantSkill hint allows a worker to fill a previously unfilled position
- **THEN** system displays something like:
  ```
  + Added: carol @ grill on Mon 9:00
  - Resolved: grill on Mon 9:00 (was unfilled)
  ```

#### Scenario: Hint has no effect
- **WHEN** a hint is added but produces no schedule changes
- **THEN** system displays "No schedule changes."

### Requirement: Apply last hint as real change
The system SHALL provide `what-if apply` that translates the most recent hint into a persistent mutation. The system SHALL execute the corresponding real command (e.g., GrantSkill becomes `worker grant-skill`), remove the applied hint from the session, and recompute from the updated context. If no hints are active, the system SHALL display "No hints to apply."

#### Scenario: Apply a GrantSkill hint
- **WHEN** the last hint is `GrantSkill carol cooking` and user types `what-if apply`
- **THEN** system executes `worker grant-skill carol cooking` (persists to database), removes the hint from the session, rebuilds the session from updated context, and confirms "Applied: grant skill cooking to carol"

#### Scenario: Apply a WaiveOvertime hint
- **WHEN** the last hint is `WaiveOvertime bob` and user types `what-if apply`
- **THEN** system executes `worker set-overtime bob on`, removes the hint, rebuilds session, and confirms "Applied: waive overtime for bob"

#### Scenario: Apply an unsupported hint type
- **WHEN** the last hint is `AddWorker` (temp worker) and user types `what-if apply`
- **THEN** system displays "Cannot apply AddWorker hints automatically. Create the worker manually with 'user create' and 'worker grant-skill', then regenerate the schedule."

#### Scenario: Apply a PinAssignment hint
- **WHEN** the last hint is `PinAssignment marco grill Mon 9:00` and user types `what-if apply`
- **THEN** system executes `pin marco grill monday 9` (persists the pin), removes the hint, rebuilds session, and confirms "Applied: pin marco at grill on monday 9:00"

#### Scenario: Apply with no hints
- **WHEN** no hints are active and user types `what-if apply`
- **THEN** system displays "No hints to apply."

### Requirement: Hints require active draft session
All `what-if` commands SHALL require an active draft session. If no draft session is active, the system SHALL display "No active draft. Start a draft session first." and not execute the hint operation.

#### Scenario: What-if without draft
- **WHEN** no draft session is active and user types `what-if grant-skill carol cooking`
- **THEN** system displays "No active draft. Start a draft session first."

#### Scenario: What-if with active draft
- **WHEN** a draft session is active and user types `what-if grant-skill carol cooking`
- **THEN** system proceeds with the hint operation normally

### Requirement: Hint session cleared on draft mutation
When a mutating command is executed within a draft session while hints are active, the system SHALL mark the hint session as stale (update the checkpoint to the current audit entry) rather than destroying it. The system SHALL display "Hint session is stale due to data change. Run 'what-if rebase' to reconcile, or continue adding hints (rebase will run automatically)." Subsequent hint operations SHALL trigger an automatic rebase before proceeding.

#### Scenario: Mutating command marks session stale
- **WHEN** hint session has 2 hints and user executes `worker grant-skill 2 1`
- **THEN** the system persists the hint session with updated checkpoint and displays "Hint session is stale due to data change. Run 'what-if rebase' to reconcile, or continue adding hints (rebase will run automatically)."

#### Scenario: Next hint operation after stale triggers rebase
- **WHEN** the hint session is stale and the user runs `what-if grant-skill carol cooking`
- **THEN** the system runs the rebase flow first, then adds the new hint if rebase succeeds

#### Scenario: Non-mutating command preserves hint session
- **WHEN** hint session has 2 hints and user executes `worker info`
- **THEN** hint session remains unchanged with 2 hints

### Requirement: Rebase command
The system SHALL provide `what-if rebase` that reconciles a stale hint session with data changes since the last checkpoint. If the session is not stale, the system SHALL display "Hint session is up to date. No rebase needed."

#### Scenario: Rebase a stale session
- **WHEN** the hint session is stale and the user runs `what-if rebase`
- **THEN** the system classifies audit changes since the checkpoint and proceeds with the rebase flow (auto-integrate compatible changes, prompt on conflicts)

#### Scenario: Rebase a fresh session
- **WHEN** the hint session is not stale and the user runs `what-if rebase`
- **THEN** the system displays "Hint session is up to date. No rebase needed."

### Requirement: Apply updates checkpoint
When `what-if apply` persists a hint as a real mutation, the system SHALL update the hint session checkpoint to include the newly created audit entry, preventing the applied mutation from being flagged as a conflict on subsequent rebase.

#### Scenario: Apply followed by rebase
- **WHEN** the user runs `what-if apply` which executes `worker grant-skill carol cooking`
- **AND** then runs `what-if rebase`
- **THEN** the system reports "Hint session is up to date. No rebase needed." (the apply's audit entry is already included in the checkpoint)
