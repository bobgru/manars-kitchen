## ADDED Requirements

### Requirement: List workers endpoint with status filter

The system SHALL provide `GET /api/workers?status=active|inactive|all` returning a JSON array of `WorkerSummaryResp` objects. The `status` query parameter SHALL filter results by `worker_status`. The endpoint SHALL exclude users with `worker_status = 'none'` regardless of filter (those are non-workers, not part of the workers domain). The endpoint SHALL require admin authentication.

The `WorkerSummaryResp` shape SHALL be:
- `name: string` — username
- `role: string` — user role
- `status: string` — `"active"` or `"inactive"`
- `isTemp: boolean` — from `worker_temp`
- `weekendOnly: boolean` — from `worker_weekend_only`
- `seniority: integer` — from `worker_seniority`

#### Scenario: Default to active workers when status omitted
- **WHEN** an admin sends `GET /api/workers` with no query string
- **THEN** the system SHALL return only workers with `worker_status = 'active'`

#### Scenario: Filter by inactive
- **WHEN** an admin sends `GET /api/workers?status=inactive`
- **THEN** the system SHALL return only workers with `worker_status = 'inactive'`

#### Scenario: Filter by all returns active and inactive but not none
- **WHEN** an admin sends `GET /api/workers?status=all` and the system has 3 active workers, 2 inactive workers, and 4 admin users with `worker_status = 'none'`
- **THEN** the response SHALL contain 5 workers and SHALL NOT contain any of the 4 admin users

#### Scenario: Invalid status value returns 400
- **WHEN** an admin sends `GET /api/workers?status=invalid`
- **THEN** the system SHALL return 400 with an error message indicating the valid values

#### Scenario: Non-admin returns 403
- **WHEN** a non-admin user sends `GET /api/workers`
- **THEN** the system SHALL return 403

#### Scenario: Empty list when no workers match filter
- **WHEN** filter is `inactive` and no workers have `worker_status = 'inactive'`
- **THEN** the system SHALL return `[]` with status 200

#### Scenario: Summary fields populated from worker config tables
- **WHEN** alice is active, has `worker_temp = true`, `worker_weekend_only = false`, and `worker_seniority = 5`
- **THEN** alice's entry in the response SHALL contain `{name: "alice", role: "...", status: "active", isTemp: true, weekendOnly: false, seniority: 5}`
