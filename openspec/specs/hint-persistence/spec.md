## ADDED Requirements

### Requirement: Hint session table
The system SHALL store hint sessions in a `hint_sessions` table with columns: `session_id` (integer, NOT NULL), `draft_id` (integer, NOT NULL), `hints_json` (text, NOT NULL), `checkpoint` (integer, NOT NULL referencing `audit_log.id`), `created_at` (text), `updated_at` (text). The primary key SHALL be `(session_id, draft_id)`.

#### Scenario: Table exists after schema initialization
- **WHEN** the database schema is initialized
- **THEN** the `hint_sessions` table exists with all specified columns

### Requirement: Hint JSON serialization
The system SHALL serialize the `[Hint]` list as a JSON array. Each hint SHALL be encoded as an object with a `tag` field identifying the variant and additional fields for variant-specific data. The system SHALL deserialize the JSON back to `[Hint]` faithfully, preserving order and all field values.

#### Scenario: Round-trip serialization of all hint types
- **WHEN** a list containing one of each hint type is serialized to JSON and deserialized
- **THEN** the result equals the original list

#### Scenario: GrantSkill serialization format
- **WHEN** a `GrantSkill (WorkerId 3) (SkillId 2)` hint is serialized
- **THEN** the JSON is `{"tag":"GrantSkill","workerId":3,"skillId":2}`

#### Scenario: CloseStation serialization format
- **WHEN** a `CloseStation (StationId 1) (Slot 2026-04-06 09:00 3600)` hint is serialized
- **THEN** the JSON includes `"tag":"CloseStation"`, `"stationId":1`, `"day":"2026-04-06"`, `"hour":9`, `"duration":3600`

#### Scenario: Deserialization failure
- **WHEN** the system attempts to deserialize invalid or unrecognized JSON from `hints_json`
- **THEN** the system returns a deserialization error (not a crash)

### Requirement: Save hint session
The system SHALL provide a `repoSaveHintSession` function that persists the current hint list and checkpoint for a given (session_id, draft_id). If a row already exists for that key, it SHALL be updated (upsert). The `updated_at` timestamp SHALL be set to the current time.

#### Scenario: Save new hint session
- **WHEN** `repoSaveHintSession` is called with session 1, draft 1, hints `[GrantSkill 3 2]`, checkpoint 42
- **THEN** a row is inserted into `hint_sessions` with those values

#### Scenario: Update existing hint session
- **WHEN** a hint session exists for (session 1, draft 1) and `repoSaveHintSession` is called with an updated hint list
- **THEN** the existing row is updated with the new hints_json and updated_at

### Requirement: Load hint session
The system SHALL provide a `repoLoadHintSession` function that retrieves the persisted hint list and checkpoint for a given (session_id, draft_id). It SHALL return `Nothing` if no session exists for that key.

#### Scenario: Load existing hint session
- **WHEN** `repoLoadHintSession` is called for (session 1, draft 1) and a row exists
- **THEN** the system returns `Just (hints, checkpoint)`

#### Scenario: Load nonexistent hint session
- **WHEN** `repoLoadHintSession` is called for (session 5, draft 3) and no row exists
- **THEN** the system returns `Nothing`

### Requirement: Delete hint session
The system SHALL provide a `repoDeleteHintSession` function that removes the persisted hint session for a given (session_id, draft_id). Deleting a nonexistent session SHALL be a no-op.

#### Scenario: Delete existing hint session
- **WHEN** `repoDeleteHintSession` is called for (session 1, draft 1) and a row exists
- **THEN** the row is removed and subsequent `repoLoadHintSession` returns `Nothing`

#### Scenario: Delete nonexistent hint session
- **WHEN** `repoDeleteHintSession` is called for (session 5, draft 3) and no row exists
- **THEN** no error occurs

### Requirement: Auto-save on hint operations
The system SHALL automatically persist the hint session to SQLite after every hint operation that modifies the hint list (add hint, revert, revert-all, apply). The checkpoint SHALL be updated to the latest audit log entry ID at the time of save.

#### Scenario: Adding a hint triggers auto-save
- **WHEN** the user adds a hint via `what-if grant-skill carol cooking`
- **THEN** the updated hint list is persisted to `hint_sessions` before displaying the diff

#### Scenario: Reverting triggers auto-save
- **WHEN** the user reverts the last hint via `what-if revert`
- **THEN** the updated hint list (with last hint removed) is persisted

#### Scenario: Revert-all triggers auto-save
- **WHEN** the user reverts all hints via `what-if revert-all`
- **THEN** an empty hint list is persisted (session row retained with checkpoint)

### Requirement: Resume hint session on draft open
The system SHALL check for a persisted hint session when a draft is opened. If one exists, the system SHALL offer to resume it. On acceptance, the system SHALL rebuild the `Session` from the current database state with the persisted hints applied.

#### Scenario: Resume persisted session
- **WHEN** the user opens draft 1 and a persisted hint session exists with 2 hints
- **THEN** the system displays "Found saved hint session (2 hints). Resume? [Y/n]"
- **AND** on confirmation, the system rebuilds the scheduler context, applies the 2 hints, and displays "Resumed hint session with 2 hints."

#### Scenario: Decline resume
- **WHEN** the user opens draft 1 and a persisted hint session exists and the user declines
- **THEN** the persisted session is deleted and the draft opens with no hints

#### Scenario: No persisted session
- **WHEN** the user opens draft 1 and no persisted hint session exists
- **THEN** the draft opens normally with no hint session

### Requirement: Delete hint session on draft commit or discard
The system SHALL delete any persisted hint session associated with a draft when that draft is committed or discarded.

#### Scenario: Draft commit cleans up hint session
- **WHEN** draft 1 has a persisted hint session and the user runs `draft commit 1`
- **THEN** the hint session row for draft 1 is deleted

#### Scenario: Draft discard cleans up hint session
- **WHEN** draft 1 has a persisted hint session and the user runs `draft discard 1`
- **THEN** the hint session row for draft 1 is deleted
