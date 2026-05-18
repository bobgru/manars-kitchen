# Worker Deactivate

Provides `worker deactivate <name>` and `worker activate <name>` to take a worker out of active scheduling while preserving configuration. Inactive workers are excluded from scheduler context but their skills, prefs, and employment rows are kept for later reactivation.

## Requirements

### Requirement: Deactivate a worker, preserving configuration
The system SHALL provide `worker deactivate <name>` that resolves `<name>` to a `WorkerId` and previews the deactivation impact: the counts of `pinned_assignments`, `draft_assignments`, and `calendar_assignments WHERE slot_date >= today()` rows that reference the worker. If all three counts are zero, the system SHALL commit the deactivation: transition `worker_status` from `active` to `inactive`, set `deactivated_at` to today, and report success. If any count is nonzero, the system SHALL NOT modify state and SHALL report the impact counts to the user, instructing them to use `worker force-deactivate <name>` to commit.

When `worker force-deactivate <name>` is invoked, the system SHALL transition `worker_status` from `active` to `inactive`, set `deactivated_at` to today, remove the worker from `pinned_assignments`, from `draft_assignments` for any draft, and from `calendar_assignments WHERE slot_date >= today()`. The system SHALL preserve all rows in `worker_*` configuration tables (skills, employment, hours, prefs, variety, shift prefs, weekend-only, seniority, cross-training, pairing). The system SHALL preserve past `calendar_assignments` (slot_date < today()) and named-schedule `assignments`. The CLI message SHALL report the counts of pins, draft entries, and future calendar slots removed.

`PUT /api/workers/:name/deactivate` SHALL implement the safe variant: respond `204 No Content` on zero-impact commit, or `409 Conflict` with body `{pinsRemoved, draftsRemoved, calendarRemoved}` and no state change when impact is nonzero. `PUT /api/workers/:name/deactivate/force` SHALL implement the force variant.

#### Scenario: Deactivate an active worker with zero impact
- **WHEN** an admin runs `worker deactivate alice` and alice has zero pins, zero draft entries, and zero future calendar entries
- **THEN** the system commits the deactivation, sets alice's `worker_status` to `inactive` and `deactivated_at` to today, and prints "Deactivated alice."

#### Scenario: Deactivate previews impact without committing
- **WHEN** an admin runs `worker deactivate alice` and alice has 3 pinned assignments, appears 2 times in an open draft, and has 8 calendar entries dated today or later
- **THEN** the system reports the counts (3 pins, 2 draft entries, 8 future calendar slots), does NOT change `worker_status`, and instructs the user to run `worker force-deactivate alice` to commit

#### Scenario: Force-deactivate commits and removes references
- **WHEN** an admin runs `worker force-deactivate alice` and alice has 3 pinned assignments, 2 draft entries, 8 future calendar slots
- **THEN** the system sets alice's `worker_status` to `inactive`, sets `deactivated_at` to today, removes those 13 entries, and prints "Deactivated alice. Removed 3 pins, 2 draft entries, 8 future calendar slots."

#### Scenario: Deactivation preserves configuration
- **WHEN** an admin runs `worker force-deactivate alice` and alice has skills, station prefs, and an employment record
- **THEN** the rows in `worker_skills`, `worker_station_prefs`, and `worker_employment` are unchanged; `worker view alice` continues to show them

#### Scenario: Deactivation preserves past calendar history
- **WHEN** an admin runs `worker force-deactivate alice` and alice has calendar entries from earlier this month
- **THEN** the past entries (slot_date < today()) remain; only entries dated today or later are removed

#### Scenario: Deactivate already-inactive worker
- **WHEN** an admin runs `worker deactivate alice` and alice's `worker_status` is already `inactive`
- **THEN** the system reports that alice is already inactive; no changes are made

#### Scenario: Deactivate a non-worker user
- **WHEN** an admin runs `worker deactivate bob` and bob has `worker_status = 'none'`
- **THEN** the system prints an error indicating that bob is not a worker

#### Scenario: REST PUT /api/workers/:name/deactivate with zero impact
- **WHEN** an admin sends `PUT /api/workers/alice/deactivate` and alice has zero pins, drafts, and future calendar entries
- **THEN** the system commits the deactivation and returns 204 No Content

#### Scenario: REST PUT /api/workers/:name/deactivate with nonzero impact returns 409
- **WHEN** an admin sends `PUT /api/workers/alice/deactivate` and alice has nonzero pins, drafts, or future calendar entries
- **THEN** the system returns 409 Conflict with JSON body `{"pinsRemoved": N, "draftsRemoved": N, "calendarRemoved": N}` and alice's status is unchanged

#### Scenario: REST PUT /api/workers/:name/deactivate/force commits unconditionally
- **WHEN** an admin sends `PUT /api/workers/alice/deactivate/force`
- **THEN** the system commits the deactivation regardless of impact and returns 200 OK with the removed counts

#### Scenario: Audit log records deactivate, force-deactivate, and activate
- **WHEN** `worker deactivate <name>` (zero-impact path), `worker force-deactivate <name>`, or `worker activate <name>` succeeds
- **THEN** an audit entry is logged with operation `deactivate`, `force-deactivate`, or `activate` respectively, entity type `worker`, and entity id of the worker_id

### Requirement: Reactivate an inactive worker
The system SHALL provide `worker activate <name>` that transitions `worker_status` from `inactive` back to `active` and clears `deactivated_at`. Configuration rows in `worker_*` tables remain effective. The system SHALL NOT restore previously-cleared pins, drafts, or calendar entries.

#### Scenario: Reactivate an inactive worker
- **WHEN** an admin runs `worker activate alice` and alice's status is `inactive` with `deactivated_at` set
- **THEN** the system sets `worker_status = 'active'` and clears `deactivated_at`; alice's preserved configuration is now in effect again; no pins or calendar entries are restored

#### Scenario: Reactivate already-active worker
- **WHEN** an admin runs `worker activate alice` and alice is already active
- **THEN** the system reports that alice is already active; no changes are made

#### Scenario: REST PUT /api/workers/:name/activate
- **WHEN** an admin sends `PUT /api/workers/alice/activate` and alice is inactive
- **THEN** the system reactivates alice and returns 200

### Requirement: Scheduler ignores inactive workers
The scheduler and `WorkerContext` loader SHALL only consider workers with `worker_status = 'active'`. Workers with status `inactive` or `none` SHALL NOT appear in the loaded `WorkerContext` and SHALL NOT be eligible for auto-assignment, hint generation, or any operation that scans the worker pool.

#### Scenario: Scheduler does not assign an inactive worker
- **WHEN** the scheduler is run and `alice` has `worker_status = 'inactive'`
- **THEN** alice does not appear in the loaded `WorkerContext`; alice is not auto-assigned; and any hint engine pass that scans workers does not enumerate alice
