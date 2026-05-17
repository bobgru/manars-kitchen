## ADDED Requirements

### Requirement: Permanently remove the worker concept with safe-delete check
The system SHALL provide `worker delete <name>` that permanently removes the worker concept by setting `users.worker_status = 'none'`. The user account SHALL remain. The operation SHALL first check for references across all worker tables (configuration: `worker_skills`, `worker_hours`, `worker_overtime_optin`, `worker_station_prefs`, `worker_prefers_variety`, `worker_shift_prefs`, `worker_weekend_only`, `worker_seniority`, `worker_avoid_pairing`, `worker_prefer_pairing`, `worker_cross_training`, `worker_employment`; schedule and history: `pinned_assignments`, `calendar_assignments` (any date), `draft_assignments`, `assignments`, `absence_requests`, `yearly_allowances`). If ANY references exist, the system SHALL block the operation and report the references grouped by configuration vs. schedule, suggesting `worker deactivate` instead, or `worker force-delete` to cascade.

### Requirement: Force-delete a worker by cascading all references
The system SHALL provide `worker force-delete <name>` that DELETEs all rows from worker reference tables (configuration AND schedule/history) for the worker_id, then sets `users.worker_status = 'none'`. The user account SHALL remain.

#### Scenario: Delete a worker with no references
- **WHEN** an admin runs `worker delete alice` and alice has no rows in any worker reference table
- **THEN** the system sets `users.worker_status = 'none'` for alice and prints success

#### Scenario: Delete blocks when worker has configuration refs
- **WHEN** an admin runs `worker delete alice` and alice has rows in `worker_skills` or `worker_employment`
- **THEN** the system blocks the operation and prints the configuration references; no changes are made; the message suggests `worker deactivate` to take alice out of scheduling while preserving config

#### Scenario: Delete blocks when worker has schedule or history refs
- **WHEN** an admin runs `worker delete alice` and alice has rows in `assignments` or `calendar_assignments`
- **THEN** the system blocks the operation and prints the schedule/history references; no changes are made

#### Scenario: Force-delete cascades configuration and schedule
- **WHEN** an admin runs `worker force-delete alice` for a worker with skills, employment, calendar history, and assignments
- **THEN** the system removes all rows for alice's worker_id from `worker_*`, `pinned_assignments`, `calendar_assignments`, `draft_assignments`, `assignments`, `absence_requests`, and `yearly_allowances`; sets `users.worker_status = 'none'` for alice; alice can still log in

#### Scenario: Delete a non-worker user
- **WHEN** an admin runs `worker delete bob` and bob has `worker_status = 'none'`
- **THEN** the system prints an error indicating that bob is not a worker

#### Scenario: Delete an inactive worker that still has refs
- **WHEN** an admin runs `worker delete alice` and alice's status is `inactive` with preserved configuration in `worker_skills`
- **THEN** the system blocks the delete and reports the configuration references; force-delete would be required

#### Scenario: REST DELETE /api/workers/:name with refs returns 409
- **WHEN** an admin DELETEs `/api/workers/alice` and alice has refs
- **THEN** the system returns 409 with a `WorkerReferencesResp` body listing the references grouped by configuration and schedule

#### Scenario: REST DELETE /api/workers/:name without refs returns 204
- **WHEN** an admin DELETEs `/api/workers/alice` and alice has no refs
- **THEN** the system returns 204; alice's user record now has `worker_status = 'none'`

#### Scenario: REST DELETE /api/workers/:name/force cascades
- **WHEN** an admin DELETEs `/api/workers/alice/force`
- **THEN** the system cascades and returns 204; alice's user record has `worker_status = 'none'`

#### Scenario: Audit log records delete and force-delete
- **WHEN** `worker delete <name>` or `worker force-delete <name>` succeeds
- **THEN** an audit entry is logged with operation `delete` or `force-delete`, entity type `worker`, and entity id of the worker_id
