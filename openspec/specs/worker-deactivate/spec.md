# Worker Deactivate

Provides `worker deactivate <name>` and `worker activate <name>` to take a worker out of active scheduling while preserving configuration. Inactive workers are excluded from scheduler context but their skills, prefs, and employment rows are kept for later reactivation.

## Requirements

### Requirement: Deactivate a worker, preserving configuration
The system SHALL provide `worker deactivate <name>` that resolves `<name>` to a `WorkerId` and transitions the worker's `worker_status` from `active` to `inactive`. The system SHALL set `deactivated_at` to today's date. The system SHALL remove the worker from `pinned_assignments`, from `draft_assignments` for any draft, and from `calendar_assignments WHERE slot_date >= today()`. The system SHALL preserve all rows in `worker_*` configuration tables (skills, employment, hours, prefs, variety, shift prefs, weekend-only, seniority, cross-training, pairing). The system SHALL preserve past `calendar_assignments` (slot_date < today()) and named-schedule `assignments`. The CLI message SHALL report the counts of pins, draft entries, and future calendar slots removed.

### Requirement: Reactivate an inactive worker
The system SHALL provide `worker activate <name>` that transitions `worker_status` from `inactive` back to `active` and clears `deactivated_at`. Configuration rows in `worker_*` tables remain effective. The system SHALL NOT restore previously-cleared pins, drafts, or calendar entries.

### Requirement: Scheduler ignores inactive workers
The scheduler and `WorkerContext` loader SHALL only consider workers with `worker_status = 'active'`. Workers with status `inactive` or `none` SHALL NOT appear in the loaded `WorkerContext` and SHALL NOT be eligible for auto-assignment, hint generation, or any operation that scans the worker pool.

#### Scenario: Deactivate an active worker with pins, drafts, and future calendar
- **WHEN** an admin runs `worker deactivate alice` and alice has 3 pinned assignments, appears 2 times in an open draft, and has 8 calendar entries dated today or later
- **THEN** the system sets alice's `worker_status` to `inactive` and `deactivated_at` to today, removes those 13 entries, and prints a summary like "Deactivated alice. Removed 3 pins, 2 draft entries, 8 future calendar slots."

#### Scenario: Deactivation preserves configuration
- **WHEN** an admin runs `worker deactivate alice` and alice has skills, station prefs, and an employment record
- **THEN** the rows in `worker_skills`, `worker_station_prefs`, and `worker_employment` are unchanged; `worker view alice` continues to show them

#### Scenario: Deactivation preserves past calendar history
- **WHEN** an admin runs `worker deactivate alice` and alice has calendar entries from earlier this month
- **THEN** the past entries (slot_date < today()) remain; only entries dated today or later are removed

#### Scenario: Deactivate already-inactive worker
- **WHEN** an admin runs `worker deactivate alice` and alice's `worker_status` is already `inactive`
- **THEN** the system reports that alice is already inactive; no changes are made

#### Scenario: Deactivate a non-worker user
- **WHEN** an admin runs `worker deactivate bob` and bob has `worker_status = 'none'`
- **THEN** the system prints an error indicating that bob is not a worker

#### Scenario: Reactivate an inactive worker
- **WHEN** an admin runs `worker activate alice` and alice's status is `inactive` with `deactivated_at` set
- **THEN** the system sets `worker_status = 'active'` and clears `deactivated_at`; alice's preserved configuration is now in effect again; no pins or calendar entries are restored

#### Scenario: Reactivate already-active worker
- **WHEN** an admin runs `worker activate alice` and alice is already active
- **THEN** the system reports that alice is already active; no changes are made

#### Scenario: Scheduler does not assign an inactive worker
- **WHEN** the scheduler is run and `alice` has `worker_status = 'inactive'`
- **THEN** alice does not appear in the loaded `WorkerContext`; alice is not auto-assigned; and any hint engine pass that scans workers does not enumerate alice

#### Scenario: REST PUT /api/workers/:name/deactivate
- **WHEN** an admin sends `PUT /api/workers/alice/deactivate`
- **THEN** the system performs the deactivation and returns 200 with a JSON body containing the removed counts

#### Scenario: REST PUT /api/workers/:name/activate
- **WHEN** an admin sends `PUT /api/workers/alice/activate` and alice is inactive
- **THEN** the system reactivates alice and returns 200

#### Scenario: Audit log records deactivate and activate
- **WHEN** `worker deactivate <name>` or `worker activate <name>` succeeds
- **THEN** an audit entry is logged with operation `deactivate` or `activate`, entity type `worker`, and entity id of the worker_id
