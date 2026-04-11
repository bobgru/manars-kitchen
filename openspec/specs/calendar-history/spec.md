## ADDED Requirements

### Requirement: History snapshot on calendar commit
When assignments are committed to the calendar for a date range, the system SHALL first snapshot all existing assignments in that range into the history log before overwriting them. Each snapshot SHALL record the date range, a timestamp, and an optional user-provided note.

#### Scenario: Commit creates history entry
- **WHEN** a schedule is committed to the calendar for Apr 1-30 with note "April schedule"
- **THEN** a history commit is created with the current timestamp, date range Apr 1-30, and note "April schedule"
- **AND** all pre-existing calendar assignments for Apr 1-30 are stored as that commit's snapshot

#### Scenario: Commit to empty range creates minimal history
- **WHEN** a schedule is committed to a date range with no existing assignments
- **THEN** a history commit is still created (with an empty snapshot) to record that the commit occurred

### Requirement: List calendar history
The system SHALL support listing all history commits in reverse chronological order, showing commit id, timestamp, date range, and note.

#### Scenario: List history with multiple commits
- **WHEN** three commits have been made (April initial, April reschedule, May initial)
- **THEN** listing returns all three in reverse chronological order with their metadata

#### Scenario: List history when empty
- **WHEN** no commits have been made
- **THEN** listing returns an empty list

### Requirement: View historical snapshot
The system SHALL support loading the snapshot of replaced assignments for a specific history commit, returning them as a `Schedule` domain type.

#### Scenario: View what was replaced
- **WHEN** commit #2 replaced Apr 15-30 assignments during a reschedule
- **THEN** loading commit #2's snapshot returns the original Apr 15-30 assignments that were overwritten

#### Scenario: View snapshot of empty overwrite
- **WHEN** commit #1 was the first commit (nothing existed before)
- **THEN** loading commit #1's snapshot returns an empty `Schedule`

### Requirement: History stored in two tables
History SHALL be stored using a `calendar_commits` table (commit metadata) and a `calendar_commit_assignments` table (snapshot assignment rows keyed by commit id). This enables SQL-level queries over historical assignments.

#### Scenario: History tables exist after schema init
- **WHEN** the database schema is initialized
- **THEN** both `calendar_commits` and `calendar_commit_assignments` tables exist
