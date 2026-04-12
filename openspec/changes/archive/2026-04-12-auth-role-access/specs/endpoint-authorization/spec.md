## ADDED Requirements

### Requirement: Admin-only endpoint enforcement
The following endpoint categories SHALL be restricted to users with `Admin` role. A `Normal` user attempting to access these SHALL receive `403` with `{"error": "Forbidden"}`:

- Skill CRUD: `POST /api/skills`, `DELETE /api/skills/:id`
- Station CRUD: `POST /api/stations`, `DELETE /api/stations/:id`, `PUT /api/stations/:id/hours`, `PUT /api/stations/:id/closure`
- Shift CRUD: `POST /api/shifts`, `DELETE /api/shifts/:name`
- Schedule management: `DELETE /api/schedules/:name`
- Draft management: `POST /api/drafts`, `POST /api/drafts/:id/generate`, `POST /api/drafts/:id/commit`, `DELETE /api/drafts/:id`
- Calendar mutations: `POST /api/calendar/unfreeze`
- Config writes: `PUT /api/config/:key`, `POST /api/config/presets/:name`, `POST /api/config/reset`, `PUT /api/config/pay-period`
- Checkpoints: `POST /api/checkpoints`, `POST /api/checkpoints/:name/commit`, `POST /api/checkpoints/:name/rollback`
- Import/export: `GET /api/export`, `POST /api/import`
- User management: `GET /api/users`, `POST /api/users`, `DELETE /api/users/:username`
- Absence type management: `POST /api/absence-types`, `DELETE /api/absence-types/:id`, `PUT /api/absence-types/:id/allowance`
- Absence approval/rejection: `POST /api/absences/:id/approve`, `POST /api/absences/:id/reject`
- Pin management: `POST /api/pins`, `DELETE /api/pins`
- Audit log: `GET /api/audit`

#### Scenario: Admin accesses admin-only endpoint
- **WHEN** an admin user makes a POST to `/api/skills` with valid data
- **THEN** the request succeeds

#### Scenario: Worker accesses admin-only endpoint
- **WHEN** a normal user makes a POST to `/api/skills`
- **THEN** the response is `403` with `{"error": "Forbidden"}`

#### Scenario: Worker cannot create drafts
- **WHEN** a normal user makes a POST to `/api/drafts`
- **THEN** the response is `403` with `{"error": "Forbidden"}`

#### Scenario: Worker cannot manage users
- **WHEN** a normal user makes a GET to `/api/users`
- **THEN** the response is `403` with `{"error": "Forbidden"}`

### Requirement: Worker-accessible read-only endpoints
The following read-only endpoints SHALL be accessible to all authenticated users (both `Admin` and `Normal`):

- `GET /api/skills`
- `GET /api/stations`
- `GET /api/shifts`
- `GET /api/schedules` and `GET /api/schedules/:name`
- `GET /api/calendar` and `GET /api/calendar/history` and `GET /api/calendar/history/:id`
- `GET /api/config`
- `GET /api/calendar/freeze-status`
- `GET /api/drafts` and `GET /api/drafts/:id` (read-only view)
- `GET /api/pins`

#### Scenario: Worker reads skills
- **WHEN** a normal user makes a GET to `/api/skills`
- **THEN** the request succeeds with `200`

#### Scenario: Worker reads calendar
- **WHEN** a normal user makes a GET to `/api/calendar?from=2026-05-01&to=2026-05-07`
- **THEN** the request succeeds with `200`

### Requirement: Worker self-scoping for worker endpoints
A `Normal` user SHALL only be able to access `PUT /api/workers/:id/*` endpoints when the `:id` matches their own `userWorkerId`. Requests targeting a different worker ID SHALL return `403`.

#### Scenario: Worker updates own preferences
- **WHEN** a normal user with `workerId = 3` makes a PUT to `/api/workers/3/prefs`
- **THEN** the request succeeds

#### Scenario: Worker updates another worker's preferences
- **WHEN** a normal user with `workerId = 3` makes a PUT to `/api/workers/5/prefs`
- **THEN** the response is `403` with `{"error": "Forbidden"}`

#### Scenario: Admin updates any worker's preferences
- **WHEN** an admin user makes a PUT to `/api/workers/5/prefs`
- **THEN** the request succeeds (admin bypasses self-scoping)

### Requirement: Worker self-scoping for absence requests
A `Normal` user SHALL only be able to create absence requests (`POST /api/absences`) where the `workerId` in the request body matches their own `userWorkerId`. The `GET /api/absences/pending` endpoint SHALL return only the worker's own pending absences for `Normal` users, and all pending absences for `Admin` users.

#### Scenario: Worker requests own absence
- **WHEN** a normal user with `workerId = 3` posts an absence request with `workerId = 3`
- **THEN** the request succeeds

#### Scenario: Worker requests absence for another worker
- **WHEN** a normal user with `workerId = 3` posts an absence request with `workerId = 5`
- **THEN** the response is `403` with `{"error": "Forbidden"}`

#### Scenario: Worker sees only own pending absences
- **WHEN** a normal user with `workerId = 3` makes a GET to `/api/absences/pending`
- **THEN** the response contains only absence requests where `workerId = 3`

#### Scenario: Admin sees all pending absences
- **WHEN** an admin user makes a GET to `/api/absences/pending`
- **THEN** the response contains all pending absence requests

### Requirement: Worker self-scoping for hint sessions
A `Normal` user SHALL only be able to access hint endpoints for sessions that belong to them. The `sessionId` parameter in hint requests SHALL be validated against the authenticated user's sessions.

#### Scenario: Worker accesses own hint session
- **WHEN** a normal user accesses hints for a session they own
- **THEN** the request succeeds

#### Scenario: Worker accesses another user's hint session
- **WHEN** a normal user accesses hints for a session owned by a different user
- **THEN** the response is `403` with `{"error": "Forbidden"}`
