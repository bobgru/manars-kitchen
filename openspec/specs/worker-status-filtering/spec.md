# Worker Status Filtering

Constrains the scheduler and `WorkerContext` loaders to consider only workers with `worker_status = 'active'`, and declares foreign keys from worker tables back to `users`. Inactive and non-worker users are excluded from scheduling reads while their configuration rows are preserved.

## Requirements

### Requirement: WorkerContext loaders filter to active workers
`repoLoadWorkerCtx` and `repoLoadEmployment` SHALL inner-join `users` on `worker_id = users.id` and filter to `users.worker_status = 'active'`. Only active workers SHALL appear in the loaded `WorkerContext`. The same filter SHALL apply to any repository function that returns a list of `WorkerId` values intended for scheduling.

### Requirement: Foreign keys from worker tables to users
Every `worker_*.worker_id` column SHALL declare `REFERENCES users(id) ON DELETE RESTRICT`. The schedule-shaped tables (`pinned_assignments`, `calendar_assignments`, `draft_assignments`, `assignments`, `absence_requests`, `yearly_allowances`) SHALL also declare the foreign key on their `worker_id` column.

#### Scenario: Inactive worker is absent from WorkerContext
- **WHEN** the system calls `repoLoadWorkerCtx` and the database contains alice (active) and bob (inactive)
- **THEN** the returned `WorkerContext` mentions alice but not bob in any of its fields

#### Scenario: Non-worker user is absent from WorkerContext
- **WHEN** the system calls `repoLoadWorkerCtx` and the database contains alice (active) and admin-only user carol (`worker_status = 'none'`)
- **THEN** the returned `WorkerContext` mentions alice but not carol

#### Scenario: Force-deleting a user with FK refs is blocked at the DB layer if config or schedule rows still exist
- **WHEN** any code path attempts to DELETE FROM users WHERE id = ? while `worker_*` rows still reference it
- **THEN** the FK constraint blocks the delete; the application layer (`Service/User.forceDeleteUser`) SHALL clear references before deleting

#### Scenario: Inactive worker is preserved in worker_* tables
- **WHEN** alice is deactivated and her configuration rows remain
- **THEN** her `worker_skills`, `worker_employment`, etc. rows are still present; only the WorkerContext loader filters them out at read time
