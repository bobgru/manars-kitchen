## MODIFIED Requirements

### Requirement: Admin-only endpoint enforcement
The following endpoint categories SHALL be restricted to users with `Admin` role. A `Normal` user attempting to access these SHALL receive `403` with `{"error": "Forbidden"}`:

- Skill CRUD: `POST /api/skills`, `DELETE /api/skills/:id`
- Station CRUD: `POST /api/stations`, `DELETE /api/stations/:id`, `PUT /api/stations/:id/hours`, `PUT /api/stations/:id/closure`
- Shift CRUD: `POST /api/shifts`, `DELETE /api/shifts/:name`
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
- `GET /api/calendar` and `GET /api/calendar/history` and `GET /api/calendar/history/:id`
- `GET /api/config`
- `GET /api/calendar/freeze-status`
- `GET /api/drafts` and `GET /api/drafts/:id` (read-only view)
- `GET /api/pins`
