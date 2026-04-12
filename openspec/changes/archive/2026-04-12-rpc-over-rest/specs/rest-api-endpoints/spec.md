## ADDED Requirements

### Requirement: Skill create endpoint
The system SHALL expose `POST /api/skills` accepting a JSON body with `id`, `name`, and `description` fields, creating a new skill and returning 201.

#### Scenario: Create a skill
- **WHEN** a POST is made to `/api/skills` with `{"id": 4, "name": "pastry", "description": "Pastry skills"}`
- **THEN** the response is `201`
- **AND** `GET /api/skills` includes the new skill

### Requirement: Skill delete endpoint
The system SHALL expose `DELETE /api/skills/:id` which deletes the skill and returns 204.

#### Scenario: Delete a skill
- **WHEN** a skill with ID 4 exists
- **AND** a DELETE is made to `/api/skills/4`
- **THEN** the response is `204`
- **AND** `GET /api/skills` no longer includes skill 4

### Requirement: Station create endpoint
The system SHALL expose `POST /api/stations` accepting a JSON body with `id` and `name` fields, returning 201.

#### Scenario: Create a station
- **WHEN** a POST is made to `/api/stations` with `{"id": 1, "name": "grill"}`
- **THEN** the response is `201`
- **AND** `GET /api/stations` includes the new station

### Requirement: Station delete endpoint
The system SHALL expose `DELETE /api/stations/:id` which deletes the station and returns 204.

#### Scenario: Delete a station
- **WHEN** a DELETE is made to `/api/stations/1`
- **THEN** the response is `204`

### Requirement: Station hours endpoint
The system SHALL expose `PUT /api/stations/:id/hours` accepting a JSON body with hours configuration.

#### Scenario: Set station hours
- **WHEN** a PUT is made to `/api/stations/1/hours` with hours configuration
- **THEN** the response is `200`

### Requirement: Station closure endpoint
The system SHALL expose `PUT /api/stations/:id/closure` accepting a JSON body with closure dates.

#### Scenario: Set station closure
- **WHEN** a PUT is made to `/api/stations/1/closure` with `{"dates": ["2026-04-06"]}`
- **THEN** the response is `200`

### Requirement: Shift create endpoint
The system SHALL expose `POST /api/shifts` accepting a JSON body with `name`, `start`, and `duration` fields, returning 201.

#### Scenario: Create a shift
- **WHEN** a POST is made to `/api/shifts` with `{"name": "morning", "start": 6, "duration": 8}`
- **THEN** the response is `201`

### Requirement: Shift delete endpoint
The system SHALL expose `DELETE /api/shifts/:name` which deletes the shift and returns 204.

#### Scenario: Delete a shift
- **WHEN** a DELETE is made to `/api/shifts/morning`
- **THEN** the response is `204`

### Requirement: Worker configuration endpoints
The system SHALL expose PUT endpoints under `/api/workers/:id/` for all worker configuration:
- `PUT /api/workers/:id/hours` — set weekly hours
- `PUT /api/workers/:id/overtime` — set overtime preference
- `PUT /api/workers/:id/prefs` — set station preferences
- `PUT /api/workers/:id/variety` — set variety preference
- `PUT /api/workers/:id/shift-prefs` — set shift preferences
- `PUT /api/workers/:id/weekend-only` — set weekend-only flag
- `PUT /api/workers/:id/seniority` — set seniority rank
- `PUT /api/workers/:id/cross-training` — set cross-training level
- `PUT /api/workers/:id/employment-status` — set salaried/FT/PT/per-diem
- `PUT /api/workers/:id/overtime-model` — set overtime model (eligible/manual/exempt)
- `PUT /api/workers/:id/pay-tracking` — set pay period tracking
- `PUT /api/workers/:id/temp` — set temporary worker flag

#### Scenario: Set worker hours
- **WHEN** a PUT is made to `/api/workers/2/hours` with `{"hours": 40}`
- **THEN** the response is `200`

#### Scenario: Set employment status
- **WHEN** a PUT is made to `/api/workers/2/employment-status` with `{"status": "full-time"}`
- **THEN** the response is `200`

### Requirement: Worker skill grant/revoke endpoints
The system SHALL expose `POST /api/workers/:id/skills/:skillId` (grant) and `DELETE /api/workers/:id/skills/:skillId` (revoke).

#### Scenario: Grant and revoke skill
- **WHEN** a POST is made to `/api/workers/2/skills/1`
- **THEN** the response is `200`
- **AND** a DELETE to `/api/workers/2/skills/1` returns `200`

### Requirement: Worker pairing endpoints
The system SHALL expose `POST /api/workers/:id/avoid-pairing` and `POST /api/workers/:id/prefer-pairing` accepting a JSON body with `otherWorkerId`.

#### Scenario: Avoid pairing
- **WHEN** a POST is made to `/api/workers/2/avoid-pairing` with `{"otherWorkerId": 3}`
- **THEN** the response is `200`

### Requirement: Pin management endpoints
The system SHALL expose `GET /api/pins`, `POST /api/pins`, and `DELETE /api/pins/:id`.

#### Scenario: Add and list pins
- **WHEN** a POST is made to `/api/pins` with `{"workerId": 2, "stationId": 1, "date": "2026-04-06", "hour": 9}`
- **THEN** the response is `201`
- **AND** `GET /api/pins` includes the new pin

### Requirement: Calendar mutation endpoints
The system SHALL expose:
- `POST /api/calendar/commit` — commit assignments to calendar
- `POST /api/calendar/unfreeze` — temporarily unfreeze a date range
- `GET /api/calendar/freeze-status` — get freeze line and unfrozen ranges

#### Scenario: Unfreeze and check status
- **WHEN** a POST is made to `/api/calendar/unfreeze` with `{"from": "2026-04-01", "to": "2026-04-03"}`
- **THEN** the response is `200`
- **AND** `GET /api/calendar/freeze-status` includes the unfrozen range

### Requirement: Config write endpoints
The system SHALL expose:
- `PUT /api/config/:key` — set a config value
- `POST /api/config/presets/:name` — apply a preset
- `POST /api/config/reset` — reset to defaults
- `PUT /api/config/pay-period` — set pay period configuration

#### Scenario: Set config value
- **WHEN** a PUT is made to `/api/config/maxHoursPerWeek` with `{"value": 45.0}`
- **THEN** the response is `200`

### Requirement: Audit log endpoints
The system SHALL expose `GET /api/audit` returning audit log entries and `POST /api/audit/replay` to replay audit entries.

#### Scenario: Get audit log
- **WHEN** a GET is made to `/api/audit`
- **THEN** the response is `200` with a JSON array of audit entries

### Requirement: Checkpoint endpoints
The system SHALL expose:
- `GET /api/checkpoints` — list checkpoints
- `POST /api/checkpoints` — create a checkpoint
- `POST /api/checkpoints/:name/commit` — commit a checkpoint
- `POST /api/checkpoints/:name/rollback` — rollback to a checkpoint

#### Scenario: Create and list checkpoints
- **WHEN** a POST is made to `/api/checkpoints` with `{"name": "before-changes"}`
- **THEN** the response is `201`
- **AND** `GET /api/checkpoints` includes "before-changes"

### Requirement: Import/export endpoints
The system SHALL expose `GET /api/export` (full export), `GET /api/export/schedule/:name` (single schedule), and `POST /api/import` (import data).

#### Scenario: Full export
- **WHEN** a GET is made to `/api/export`
- **THEN** the response is `200` with the full system state as JSON

### Requirement: Absence type management endpoints
The system SHALL expose `POST /api/absence-types` (create), `DELETE /api/absence-types/:id` (delete), and `PUT /api/absence-types/:id/allowance` (set allowance).

#### Scenario: Create absence type
- **WHEN** a POST is made to `/api/absence-types` with `{"id": 1, "name": "vacation", "description": "Annual vacation"}`
- **THEN** the response is `201`

### Requirement: User management endpoints
The system SHALL expose `GET /api/users`, `POST /api/users`, and `DELETE /api/users/:username`.

#### Scenario: Create and list users
- **WHEN** a POST is made to `/api/users` with `{"username": "admin", "password": "secret"}`
- **THEN** the response is `201`
- **AND** `GET /api/users` includes "admin"

### Requirement: Hint session endpoints
The system SHALL expose endpoints under `/api/hints/` for what-if operations:
- `POST /api/hints/close-station` — close a station in the hint session
- `POST /api/hints/pin` — pin an assignment
- `POST /api/hints/add-worker` — add a worker
- `POST /api/hints/waive-overtime` — waive overtime for a worker
- `POST /api/hints/grant-skill` — grant a skill in the hint session
- `POST /api/hints/override-prefs` — override preferences
- `POST /api/hints/revert` — revert the last hint
- `POST /api/hints/apply` — apply all hints to the draft
- `POST /api/hints/rebase` — rebase the hint session
- `GET /api/hints` — list current hints

#### Scenario: Grant skill hint
- **WHEN** a POST is made to `/api/hints/grant-skill` with `{"workerId": 3, "skillId": 2}`
- **THEN** the response is `200` with updated hint session results

#### Scenario: Apply hints
- **WHEN** a POST is made to `/api/hints/apply`
- **THEN** the response is `200` and hint suggestions are applied to the active draft
