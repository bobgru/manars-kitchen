# audit-log Specification

## Purpose
TBD - created by archiving change structured-audit-log. Update Purpose after archive.
## Requirements
### Requirement: Structured audit log schema
The `audit_log` table SHALL be extended with columns: `entity_type TEXT`, `operation TEXT`, `entity_id INTEGER`, `target_id INTEGER`, `date_from TEXT`, `date_to TEXT`, `is_mutation INTEGER NOT NULL DEFAULT 1`, `params TEXT`, `source TEXT NOT NULL DEFAULT 'cli'`. The existing `command` column SHALL become nullable.

#### Scenario: New CLI-originated entry
- **WHEN** a mutating CLI command `"worker grant-skill 3 5"` is logged via `repoLogCommand`
- **THEN** the audit_log row contains: command="worker grant-skill 3 5", entity_type="worker", operation="grant-skill", entity_id=3, target_id=5, is_mutation=1, source="cli"

#### Scenario: Existing rows after migration
- **WHEN** the schema migration runs on a database with existing audit_log entries
- **THEN** existing rows retain their command, username, and timestamp values; new columns are NULL (except is_mutation defaults to 1 and source defaults to 'cli')

### Requirement: AuditEntry type
The system SHALL define an `AuditEntry` record type with fields for all audit_log columns: `aeId` (Int), `aeTimestamp` (String), `aeUsername` (String), `aeCommand` (Maybe String), `aeEntityType` (Maybe String), `aeOperation` (Maybe String), `aeEntityId` (Maybe Int), `aeTargetId` (Maybe Int), `aeDateFrom` (Maybe String), `aeDateTo` (Maybe String), `aeIsMutation` (Bool), `aeParams` (Maybe String), `aeSource` (String).

#### Scenario: AuditEntry fields populated from structured row
- **WHEN** an audit_log row with all structured columns populated is read
- **THEN** the resulting AuditEntry has all corresponding fields set

### Requirement: repoLogCommand internally classifies
The `repoLogCommand` function SHALL continue to accept `(username, command_string)` with no signature change. Internally, it SHALL call `classify` on the command string and INSERT both the raw command and the structured fields.

#### Scenario: Handler call site unchanged
- **WHEN** a command handler calls `repoLogCommand repo username "skill create 4 pastry"`
- **THEN** the audit_log row contains both command="skill create 4 pastry" and entity_type="skill", operation="create", entity_id=4, source="cli"

#### Scenario: Unrecognized command string
- **WHEN** repoLogCommand is called with a string that classify cannot parse
- **THEN** the audit_log row contains the raw command string; structured fields are NULL; the insert does not fail

### Requirement: repoGetAuditLog returns AuditEntry
The `repoGetAuditLog` function SHALL return `IO [AuditEntry]` instead of `IO [(String, String, String)]`.

#### Scenario: Reading structured entries
- **WHEN** repoGetAuditLog is called after structured entries have been logged
- **THEN** each AuditEntry contains populated structured fields

#### Scenario: Reading legacy entries
- **WHEN** repoGetAuditLog is called on a database with pre-migration entries
- **THEN** AuditEntry values have aeCommand populated and structured fields as Nothing/default

### Requirement: Audit display updated
The `audit` command's display handler SHALL format output using AuditEntry fields. The display format SHALL include the raw command string when available, or a rendered command string (via `render`) when only structured fields are present.

#### Scenario: Display CLI-originated entry
- **WHEN** the audit command displays an entry with both command and structured fields
- **THEN** the raw command string is shown (for fidelity to what was actually typed)

#### Scenario: Display entry without raw command
- **WHEN** the audit command displays an entry with NULL command (future REST-originated)
- **THEN** render is called on the structured fields to produce a display string

### Requirement: Replay uses AuditEntry
The `replay` command SHALL consume `[AuditEntry]`. It SHALL use `aeCommand` when present for replay (preserving current behavior). When `aeCommand` is NULL, it SHALL use `render` on the structured fields.

#### Scenario: Replay of CLI entries
- **WHEN** replay processes an entry with aeCommand = Just "worker set-hours 3 40"
- **THEN** it replays using the raw command string (same as current behavior)

