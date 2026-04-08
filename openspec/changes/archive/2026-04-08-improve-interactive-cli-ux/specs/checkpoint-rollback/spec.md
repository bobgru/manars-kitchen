## ADDED Requirements

### Requirement: Create a checkpoint
The system SHALL create a checkpoint when the user types `checkpoint create [name]`. If no name is provided, the system SHALL auto-generate a name (e.g., "checkpoint-1", "checkpoint-2"). The checkpoint SHALL capture the current database state so it can be restored later. Checkpoints SHALL support nesting (creating a checkpoint while another is active).

#### Scenario: Create named checkpoint
- **WHEN** user types `checkpoint create before-experiment`
- **THEN** system creates a checkpoint named "before-experiment" and confirms: "Checkpoint created: before-experiment"

#### Scenario: Create unnamed checkpoint
- **WHEN** user types `checkpoint create`
- **THEN** system creates a checkpoint with an auto-generated name and confirms with the generated name

#### Scenario: Nested checkpoints
- **WHEN** user creates checkpoint "A", makes changes, then creates checkpoint "B"
- **THEN** both checkpoints are active; rolling back to "A" also discards changes made after "B"

### Requirement: Commit a checkpoint
The system SHALL accept the most recent checkpoint's changes when the user types `checkpoint commit`. This makes the changes since that checkpoint permanent (relative to any outer checkpoint). If no checkpoint is active, the system SHALL display an error.

#### Scenario: Commit most recent checkpoint
- **WHEN** user has an active checkpoint and types `checkpoint commit`
- **THEN** system releases the most recent checkpoint and confirms: "Checkpoint committed: <name>"

#### Scenario: Commit with no active checkpoint
- **WHEN** no checkpoint is active and user types `checkpoint commit`
- **THEN** system displays "No active checkpoint."

### Requirement: Rollback to a checkpoint
The system SHALL revert all database changes since a checkpoint when the user types `checkpoint rollback [name]`. Without a name, it SHALL rollback to the most recent checkpoint. With a name, it SHALL rollback to the named checkpoint (also discarding any newer checkpoints). After rollback, the checkpoint remains active (user can make more changes and rollback again).

#### Scenario: Rollback to most recent checkpoint
- **WHEN** user has checkpoint "test" active, has made changes, and types `checkpoint rollback`
- **THEN** system reverts all changes since "test" was created and confirms: "Rolled back to: test"

#### Scenario: Rollback to named checkpoint
- **WHEN** user has checkpoints "A" and "B" (B created after A), and types `checkpoint rollback A`
- **THEN** system reverts all changes since "A" was created, discards checkpoint "B", and confirms

#### Scenario: Rollback with unknown name
- **WHEN** user types `checkpoint rollback nosuch`
- **THEN** system displays "Unknown checkpoint: nosuch"

### Requirement: List active checkpoints
The system SHALL display all active checkpoints when the user types `checkpoint list`, showing their names in creation order (oldest first).

#### Scenario: List checkpoints
- **WHEN** user has checkpoints "A" and "B" active
- **AND** user types `checkpoint list`
- **THEN** system displays:
  ```
  Active checkpoints:
    1. A
    2. B
  ```

#### Scenario: No active checkpoints
- **WHEN** no checkpoints are active and user types `checkpoint list`
- **THEN** system displays "No active checkpoints."
