## ADDED Requirements

### Requirement: Force-deactivate verb (CLI)

The system SHALL provide `worker force-deactivate <name>` that resolves `<name>` to a `WorkerId` and unconditionally performs the deactivation: transitions `worker_status` from `active` to `inactive`, sets `deactivated_at` to today, removes the worker from `pinned_assignments`, from `draft_assignments` for any draft, and from `calendar_assignments WHERE slot_date >= today()`. The CLI message SHALL report the counts of pins, draft entries, and future calendar slots removed.

This verb mirrors `worker force-delete` and is the commit verb of the safe-then-force protocol introduced in this change.

#### Scenario: Force-deactivate with no impact
- **WHEN** an admin runs `worker force-deactivate alice` and alice has zero pins, drafts, and future calendar entries
- **THEN** the system sets alice's status to `inactive` and reports "Deactivated alice. Removed 0 pins, 0 draft entries, 0 future calendar slots."

#### Scenario: Force-deactivate with impact
- **WHEN** an admin runs `worker force-deactivate alice` and alice has 3 pins, 2 draft entries, 8 future calendar slots
- **THEN** the system removes those 13 entries, sets status to `inactive`, and reports the counts

#### Scenario: Force-deactivate already-inactive worker
- **WHEN** an admin runs `worker force-deactivate alice` and alice is already inactive
- **THEN** the system reports that alice is already inactive; no changes are made

#### Scenario: Force-deactivate non-worker user
- **WHEN** an admin runs `worker force-deactivate bob` and bob has `worker_status = 'none'`
- **THEN** the system prints an error indicating that bob is not a worker

### Requirement: Force-deactivate endpoint (REST)

The system SHALL provide `PUT /api/workers/:name/deactivate/force` that unconditionally commits the deactivation. The response SHALL be `200 OK` with a JSON body containing `pinsRemoved`, `draftsRemoved`, `calendarRemoved` integer counts. The endpoint SHALL require admin authentication.

#### Scenario: Force-deactivate via REST returns counts
- **WHEN** an admin sends `PUT /api/workers/alice/deactivate/force` and alice has 3 pins, 2 draft entries, 8 future calendar slots
- **THEN** the system returns `200 OK` with body `{"pinsRemoved": 3, "draftsRemoved": 2, "calendarRemoved": 8}` and alice's status is now `inactive`

#### Scenario: Force-deactivate non-worker via REST returns 404
- **WHEN** an admin sends `PUT /api/workers/bob/deactivate/force` and bob has `worker_status = 'none'`
- **THEN** the system returns 404 with an error message indicating that bob is not a worker

### Requirement: Service-layer deactivation preview function

The system SHALL provide `Service.Worker.previewDeactivation :: Repository -> WorkerId -> IO DeactivateResult` that returns the counts of pins, draft entries, and future calendar slots that *would* be removed by deactivation, **without modifying any state**.

#### Scenario: Preview returns same counts as force-deactivate would remove
- **WHEN** alice has 3 pins, 2 draft entries, 8 future calendar slots and `previewDeactivation repo aliceId` is called
- **THEN** the function returns `DeactivateResult 3 2 8` and no rows are deleted

#### Scenario: Preview is idempotent
- **WHEN** `previewDeactivation` is called multiple times in a row for the same worker
- **THEN** each call returns the same counts and no state changes occur

### Requirement: Audit classifier recognizes force-deactivate

The audit command classifier SHALL classify `worker force-deactivate` as a worker mutation with operation `"force-deactivate"` and entity type `"worker"`.

#### Scenario: Force-deactivate emits worker SSE event
- **WHEN** `worker force-deactivate alice` succeeds (CLI or REST)
- **THEN** an audit/command event with `entityType = "worker"` and `operation = "force-deactivate"` SHALL be published; SSE subscribers to `worker` events SHALL receive it
