# Worker REST Name Routes

All worker-keyed REST routes use `:name` capture and resolve via the change-1 `resolveWorkerName`.

## Requirements

### Requirement: Worker-keyed REST routes use name captures
All worker-keyed REST routes that previously used `Capture "id" Int` SHALL switch to `Capture "name" Text`. Each handler SHALL resolve the name via `resolveWorkerName :: Repository -> Text -> Handler WorkerId`. The resolver SHALL return HTTP 404 for not-found users and a clearly-typed error for users with `worker_status = 'none'`.

The affected routes (parameterised by `:name`):
`PUT /api/workers/:name/hours`,
`PUT /api/workers/:name/overtime`,
`PUT /api/workers/:name/prefs`,
`PUT /api/workers/:name/variety`,
`PUT /api/workers/:name/shift-prefs`,
`PUT /api/workers/:name/weekend-only`,
`PUT /api/workers/:name/seniority`,
`POST /api/workers/:name/cross-training`,
`PUT /api/workers/:name/employment-status`,
`PUT /api/workers/:name/overtime-model`,
`PUT /api/workers/:name/pay-tracking`,
`PUT /api/workers/:name/temp`,
`POST /api/workers/:name/skills/:skillName`,
`DELETE /api/workers/:name/skills/:skillName`,
`POST /api/workers/:name/avoid-pairing`,
`POST /api/workers/:name/prefer-pairing`.

The skill captures on the skill-grant routes SHALL change from `Capture "skillId" SkillId` to `Capture "skillName" Text`, resolved via the existing skill name resolution.

The view, deactivate, activate, delete, and force-delete worker routes (added in change 1) SHALL be unchanged — they already use `:name`.

#### Scenario: PUT hours by name
- **WHEN** an admin sends `PUT /api/workers/alice/hours` with body `{"hours": 40}`
- **THEN** the system resolves `alice` to her `WorkerId` and updates her hours

#### Scenario: 404 for unknown worker name
- **WHEN** an admin sends `PUT /api/workers/ghost/hours` and no user named `ghost` exists
- **THEN** the system returns 404

#### Scenario: 404 for non-worker user
- **WHEN** an admin sends `PUT /api/workers/admin-only/hours` and `admin-only` has `worker_status = 'none'`
- **THEN** the system returns 404 with a body indicating the user is not a worker

#### Scenario: skill-grant by name
- **WHEN** an admin sends `POST /api/workers/alice/skills/grill`
- **THEN** the system resolves `alice` to her WorkerId and `grill` to its SkillId, and grants the skill

#### Scenario: skill-revoke by name
- **WHEN** an admin sends `DELETE /api/workers/alice/skills/grill`
- **THEN** the skill is revoked

#### Scenario: numeric name still resolves
- **WHEN** an admin sends `PUT /api/workers/2/hours` and a user with id 2 exists
- **THEN** the system accepts `2` as either a literal username or as a numeric WorkerId fallback, and updates the hours of the matching worker

#### Scenario: pairing endpoints take other worker by name
- **WHEN** an admin sends `POST /api/workers/alice/avoid-pairing` with body `{"name": "bob"}`
- **THEN** the system resolves both names and stores the symmetric avoid-pairing relationship
