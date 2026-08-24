## MODIFIED Requirements

### Requirement: Permanently remove the worker concept with safe-delete check
The system SHALL provide `worker delete <name>` that permanently removes the worker concept by setting `users.worker_status = 'none'`. The user account SHALL remain. The operation SHALL first check for references across all worker tables (configuration: `worker_skills`, `worker_hours`, `worker_overtime_optin`, `worker_station_prefs`, `worker_prefers_variety`, `worker_shift_prefs`, `worker_weekend_only`, `worker_seniority`, `worker_avoid_pairing`, `worker_prefer_pairing`, `worker_cross_training`, `worker_employment`; schedule and history: `pinned_assignments`, `calendar_assignments` (any date), `draft_assignments`, `absence_requests`, `yearly_allowances`). If ANY references exist, the system SHALL block the operation and report the references grouped by configuration vs. schedule, suggesting `worker deactivate` instead, or `worker force-delete` to cascade.

The named-schedule `assignments` table is no longer consulted, and the reported
reference groups no longer include a `schedule assignments` count.
`pinned_assignments`, `calendar_assignments` and `draft_assignments` cover every
table from which a worker can still be referenced by an assignment.

### Requirement: Force-delete a worker by cascading all references
The system SHALL provide `worker force-delete <name>` that DELETEs all rows from worker reference tables (configuration AND schedule/history) for the worker_id, then sets `users.worker_status = 'none'`. The user account SHALL remain. The cascade SHALL NOT touch the orphaned `assignments` table, which no build creates.

#### Scenario: Delete a worker with no references
- **WHEN** an admin runs `worker delete alice` and alice has no rows in any worker reference table
- **THEN** the system sets `users.worker_status = 'none'` for alice and prints success

#### Scenario: Delete blocks when worker has configuration refs
- **WHEN** an admin runs `worker delete alice` and alice has rows in `worker_skills` or `worker_employment`
- **THEN** the system blocks the operation and prints the configuration references; no changes are made; the message suggests `worker deactivate` to take alice out of scheduling while preserving config

#### Scenario: Delete blocks when worker has schedule or history refs
- **WHEN** an admin runs `worker delete alice` and alice has rows in `calendar_assignments` or `draft_assignments`
- **THEN** the system blocks the operation and prints the schedule/history references; no changes are made

#### Scenario: Force-delete cascades configuration and schedule
- **WHEN** an admin runs `worker force-delete alice` for a worker with skills, employment, calendar history, and draft assignments
- **THEN** the system removes all rows for alice's worker_id from `worker_*`, `pinned_assignments`, `calendar_assignments`, `draft_assignments`, `absence_requests`, and `yearly_allowances`; sets `users.worker_status = 'none'` for alice; alice can still log in

#### Scenario: Force-delete works on a database that never had the assignments table
- **WHEN** an admin runs `worker force-delete alice` against a database created by this build
- **THEN** the cascade succeeds; no statement references the absent `assignments` table

#### Scenario: Delete a non-worker user
- **WHEN** an admin runs `worker delete bob` and bob has `worker_status = 'none'`
- **THEN** the system prints an error indicating that bob is not a worker

#### Scenario: Delete an inactive worker that still has refs
- **WHEN** an admin runs `worker delete alice` and alice's status is `inactive` with preserved configuration in `worker_skills`
- **THEN** the system blocks the delete and reports the configuration references; force-delete would be required
