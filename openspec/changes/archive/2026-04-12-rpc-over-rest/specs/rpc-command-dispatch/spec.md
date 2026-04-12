## ADDED Requirements

### Requirement: RPC endpoint URL scheme
The system SHALL expose RPC endpoints under `POST /rpc/<group>/<operation>` where `<group>` is the entity/command group (e.g., `skill`, `worker`, `draft`, `calendar`, `what-if`) and `<operation>` is the specific command (e.g., `create`, `set-hours`, `generate`). All RPC endpoints SHALL accept and return `application/json`.

#### Scenario: Skill create via RPC
- **WHEN** a POST is made to `/rpc/skill/create` with body `{"id": 4, "name": "pastry", "description": "Pastry skills"}`
- **THEN** the response is `200` with an empty JSON object `{}`
- **AND** `GET /api/skills` includes the new skill

#### Scenario: Unknown RPC endpoint returns 404
- **WHEN** a POST is made to `/rpc/nonexistent/command`
- **THEN** the response is `404`

### Requirement: RPC endpoints for admin entity CRUD
The system SHALL expose RPC endpoints for all admin entity management commands: skill create/delete, station create/delete/set-hours/set-closure, shift create/delete, absence-type create/delete/set-allowance.

#### Scenario: Station create and delete via RPC
- **WHEN** a POST to `/rpc/station/create` with body `{"id": 1, "name": "grill"}` returns `200`
- **AND** a POST to `/rpc/station/delete` with body `{"stationId": 1}` is made
- **THEN** the response is `200`
- **AND** the station no longer appears in `GET /api/stations`

#### Scenario: Shift create via RPC
- **WHEN** a POST to `/rpc/shift/create` with body `{"name": "morning", "start": 6, "duration": 8}` is made
- **THEN** the response is `200`
- **AND** `GET /api/shifts` includes the new shift

### Requirement: RPC endpoints for worker configuration
The system SHALL expose RPC endpoints for all worker configuration commands: set-hours, set-overtime, set-prefs, set-variety, set-shift-prefs, set-weekend-only, set-seniority, set-cross-training, set-employment-status, set-overtime-model, set-pay-tracking, set-temp, grant-skill, revoke-skill, avoid-pairing, prefer-pairing.

#### Scenario: Worker set-hours via RPC
- **WHEN** a POST to `/rpc/worker/set-hours` with body `{"workerId": 2, "hours": 40}` is made
- **THEN** the response is `200` and the worker's configured hours are updated

#### Scenario: Worker grant-skill via RPC
- **WHEN** a POST to `/rpc/worker/grant-skill` with body `{"workerId": 2, "skillId": 1}` is made
- **THEN** the response is `200` and the worker has the skill granted

### Requirement: RPC endpoints for pin management
The system SHALL expose RPC endpoints for pin operations: add, remove, list.

#### Scenario: Pin add and list via RPC
- **WHEN** a POST to `/rpc/pin/add` with body `{"workerId": 2, "stationId": 1, "date": "2026-04-06", "hour": 9}` returns `200`
- **AND** a POST to `/rpc/pin/list` with body `{}` is made
- **THEN** the response includes the added pin

### Requirement: RPC endpoints for calendar operations
The system SHALL expose RPC endpoints for calendar mutations: commit, unfreeze, freeze-status, view, view-by-worker, view-by-station, hours, diagnose, history.

#### Scenario: Calendar unfreeze via RPC
- **WHEN** a POST to `/rpc/calendar/unfreeze` with body `{"from": "2026-04-01", "to": "2026-04-03"}` is made
- **THEN** the response is `200` and the date range is recorded as unfrozen in the session

#### Scenario: Calendar freeze-status via RPC
- **WHEN** a POST to `/rpc/calendar/freeze-status` with body `{}` is made
- **THEN** the response is `200` with the current freeze line date and any unfrozen ranges

### Requirement: RPC endpoints for config management
The system SHALL expose RPC endpoints for config operations: show, set, presets, reset, set-pay-period.

#### Scenario: Config set via RPC
- **WHEN** a POST to `/rpc/config/set` with body `{"key": "maxHoursPerWeek", "value": 45.0}` is made
- **THEN** the response is `200` and `GET /api/config` reflects the updated value

### Requirement: RPC endpoints for audit log
The system SHALL expose RPC endpoints for audit operations: list, replay.

#### Scenario: Audit list via RPC
- **WHEN** a POST to `/rpc/audit/list` with body `{}` is made
- **THEN** the response is `200` with a JSON array of audit entries

### Requirement: RPC endpoints for checkpoint operations
The system SHALL expose RPC endpoints for checkpoint operations: create, commit, rollback, list.

#### Scenario: Checkpoint create and rollback via RPC
- **WHEN** a POST to `/rpc/checkpoint/create` with body `{"name": "before-changes"}` returns `200`
- **AND** some mutations are performed
- **AND** a POST to `/rpc/checkpoint/rollback` with body `{"name": "before-changes"}` is made
- **THEN** the response is `200` and the system state is restored to the checkpoint

### Requirement: RPC endpoints for draft operations
The system SHALL expose RPC endpoints for all draft commands: create, this-month, next-month, list, open, view, generate, commit, discard, hours, diagnose.

#### Scenario: Draft this-month shortcut via RPC
- **WHEN** a POST to `/rpc/draft/this-month` with body `{}` is made
- **THEN** the response is `200` with the draft ID for a draft covering the current month

### Requirement: RPC endpoints for schedule operations
The system SHALL expose RPC endpoints for schedule commands: create, list, view, view-by-worker, view-by-station, delete, hours, diagnose, clear.

#### Scenario: Schedule view-by-worker via RPC
- **WHEN** a schedule named "week1" exists
- **AND** a POST to `/rpc/schedule/view-by-worker` with body `{"name": "week1"}` is made
- **THEN** the response is `200` with the schedule data grouped by worker

### Requirement: RPC endpoints for hint session operations
The system SHALL expose RPC endpoints for all what-if commands: close-station, pin, add-worker, waive-overtime, grant-skill, override-prefs, revert, apply, rebase, list.

#### Scenario: What-if grant-skill via RPC
- **WHEN** a hint session is active
- **AND** a POST to `/rpc/what-if/grant-skill` with body `{"workerId": 3, "skillId": 2}` is made
- **THEN** the response is `200` with the updated hint session results

#### Scenario: What-if apply via RPC
- **WHEN** a POST to `/rpc/what-if/apply` with body `{}` is made
- **THEN** the response is `200` and the hint session's suggestions are applied to the draft

### Requirement: RPC endpoints for import/export
The system SHALL expose RPC endpoints for data import and export: export-all, export-schedule, import.

#### Scenario: Export-all via RPC
- **WHEN** a POST to `/rpc/export/all` with body `{}` is made
- **THEN** the response is `200` with the full system state as JSON

### Requirement: RPC endpoints for assignment operations
The system SHALL expose RPC endpoints for direct assignment commands: assign, unassign.

#### Scenario: Assign worker to station via RPC
- **WHEN** a POST to `/rpc/assign/worker` with body `{"workerId": 2, "stationId": 1, "date": "2026-04-06", "hour": 9}` is made
- **THEN** the response is `200` and the assignment is recorded

### Requirement: RPC endpoints for user management
The system SHALL expose RPC endpoints for user commands: create, list, delete.

#### Scenario: User create via RPC
- **WHEN** a POST to `/rpc/user/create` with body `{"username": "admin", "password": "secret"}` is made
- **THEN** the response is `200` and the user is created

### Requirement: RPC endpoints for context management
The system SHALL expose RPC endpoints for session context commands: use, view, clear.

#### Scenario: Set and view context via RPC
- **WHEN** a POST to `/rpc/context/use` with body `{"entityType": "worker", "nameOrId": "marco"}` returns `200`
- **AND** a POST to `/rpc/context/view` with body `{}` is made
- **THEN** the response includes `{"worker": {"name": "marco", "id": 2}}`

### Requirement: RPC session management
The system SHALL expose `POST /rpc/session/create` and `POST /rpc/session/resume` endpoints. Session create returns a new session ID. Session resume accepts a session ID and returns it if still active, or an error if expired. All other RPC endpoints SHALL accept an `X-Session-Id` header to identify the calling session.

#### Scenario: Create and use session
- **WHEN** a POST to `/rpc/session/create` with body `{"username": "admin"}` returns a session ID
- **AND** subsequent RPC calls include `X-Session-Id: <id>`
- **THEN** the server associates those calls with the session's context and unfrozen ranges

#### Scenario: Missing session header on context-dependent command
- **WHEN** a POST to `/rpc/context/view` is made without an `X-Session-Id` header
- **THEN** the response is `400` with error "Session ID required"

### Requirement: RPC audit logging
All mutating RPC commands SHALL be logged to the audit log with `source='rpc'`. The structured metadata (entity type, operation, entity ID, target ID, date range) SHALL be derived from the typed request parameters, not by parsing a command string.

#### Scenario: RPC mutation logged with source rpc
- **WHEN** a POST to `/rpc/skill/create` with body `{"id": 4, "name": "pastry", "description": "..."}` is made
- **THEN** the audit log contains an entry with entity_type="skill", operation="create", entity_id=4, source="rpc"

#### Scenario: RPC read not logged
- **WHEN** a POST to `/rpc/schedule/list` with body `{}` is made
- **THEN** no new audit log entry is created

### Requirement: RPC JSON error responses
All RPC error responses SHALL return a JSON body of the form `{"error": "<message>"}` with appropriate HTTP status codes: `400` for invalid input, `404` for missing entities, `409` for conflicts, `500` for internal errors.

#### Scenario: Invalid input returns 400
- **WHEN** a POST to `/rpc/worker/set-hours` with body `{"workerId": 2}` (missing `hours` field) is made
- **THEN** the response is `400` with body `{"error": "Missing required field: hours"}`

#### Scenario: Missing entity returns 404
- **WHEN** a POST to `/rpc/worker/set-hours` with body `{"workerId": 999, "hours": 40}` is made and worker 999 does not exist
- **THEN** the response is `404` with body `{"error": "Worker not found: 999"}`
