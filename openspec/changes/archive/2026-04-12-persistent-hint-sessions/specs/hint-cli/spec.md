## MODIFIED Requirements

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

## ADDED Requirements

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
