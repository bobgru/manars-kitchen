## ADDED Requirements

### Requirement: Worker hour limits are per-period
The system SHALL interpret worker hour limits as per-pay-period limits rather than per-week limits. The `worker_hours` table column SHALL be named `max_period_seconds`. The domain type `WorkerContext` field SHALL be named `wcMaxPeriodHours`.

#### Scenario: Hour limit with weekly period
- **WHEN** a worker has `max_period_seconds` of 144000 (40 hours) and period type is `weekly`
- **THEN** the worker's effective limit is 40 hours per week (numerically identical to old behavior)

#### Scenario: Hour limit with biweekly period
- **WHEN** a worker has `max_period_seconds` of 288000 (80 hours) and period type is `biweekly`
- **THEN** the worker's effective limit is 80 hours per biweekly period

#### Scenario: Worker set-hours reinterpretation
- **WHEN** user types `worker set-hours Alice 80` and period type is `biweekly`
- **THEN** the value 80 is stored as 288000 seconds (80 * 3600) in `max_period_seconds`
- **AND** this represents the biweekly limit

### Requirement: Scheduler counts committed calendar hours in current pay period
When evaluating whether a worker can be assigned to a slot, the scheduler SHALL sum: (1) hours the worker is already committed to in the calendar for the current pay period, plus (2) hours assigned so far in the draft schedule being generated. The total SHALL NOT exceed the worker's per-period limit.

#### Scenario: Worker with calendar hours and draft hours
- **WHEN** a worker has 30 hours committed in the calendar for the current biweekly period
- **AND** has 10 hours assigned so far in the current draft
- **AND** the worker's per-period limit is 80 hours
- **THEN** the worker has 40 remaining hours available for assignment

#### Scenario: Worker at limit from calendar hours alone
- **WHEN** a worker has 80 hours committed in the calendar for the current biweekly period
- **AND** the worker's per-period limit is 80 hours
- **THEN** the scheduler SHALL NOT assign any additional hours to this worker (unless overtime-eligible)

#### Scenario: No calendar hours (new period)
- **WHEN** no assignments exist in the calendar for the current pay period
- **THEN** the scheduler counts only draft hours against the per-period limit (same as current behavior)

#### Scenario: Calendar hours loaded for correct period boundaries
- **WHEN** period type is `biweekly` with anchor `2026-01-05`
- **AND** the schedule being generated includes dates in the period `2026-03-30` to `2026-04-12`
- **THEN** the scheduler loads calendar hours from `2026-03-30` (inclusive) to `2026-04-13` (exclusive)

### Requirement: Scheduler pre-loads calendar hours before scheduling
The scheduler SHALL pre-compute per-worker calendar hour totals for the current pay period before scheduling begins. These totals SHALL be passed into the scheduler context as a `Map WorkerId DiffTime`. The scheduler SHALL NOT query the database during individual slot assignment checks.

#### Scenario: Calendar hours pre-loaded into context
- **WHEN** a schedule generation begins
- **THEN** the system loads calendar assignments for the current pay period's date range
- **AND** computes per-worker hour totals
- **AND** stores them in the scheduler context

#### Scenario: Pre-loaded hours are used in canAssignSlot
- **WHEN** `canAssignSlot` checks whether a worker would exceed their period limit
- **THEN** it uses the pre-loaded calendar hours plus the draft schedule hours (no database query)

### Requirement: Period hour computation replaces weekly hour computation
The function that computes a worker's hours for limit checking SHALL use pay period boundaries instead of ISO week boundaries. The function `workerWeeklyHours` SHALL be replaced by `workerPeriodHours` that accepts period start and end dates.

#### Scenario: Period hours within biweekly boundary
- **WHEN** the pay period runs from `2026-03-30` to `2026-04-13`
- **AND** a worker has assignments on `2026-04-01`, `2026-04-03`, and `2026-04-10`
- **THEN** `workerPeriodHours` counts all three days' assignments

#### Scenario: Period hours exclude assignments outside boundary
- **WHEN** the pay period runs from `2026-03-30` to `2026-04-13`
- **AND** a worker has assignments on `2026-03-28` and `2026-04-15`
- **THEN** `workerPeriodHours` does not count either day's assignments

### Requirement: Per-diem workers exempt from pay period hour tracking
Workers whose `pay_period_tracking` is `exempt` (from Change 5) SHALL be excluded from calendar-based pay period hour counting. Their hour limits SHALL be checked against only the hours in the draft schedule being generated, preserving current behavior.

#### Scenario: Exempt worker ignores calendar hours
- **WHEN** a per-diem worker has 30 hours committed in the calendar for the current pay period
- **AND** has 5 hours in the current draft
- **AND** the worker's per-period limit is 20 hours
- **THEN** the scheduler checks only the 5 draft hours against the 20-hour limit (not 35 total)

#### Scenario: Standard worker includes calendar hours
- **WHEN** a standard (non-exempt) worker has 30 hours committed in the calendar for the current pay period
- **AND** has 5 hours in the current draft
- **AND** the worker's per-period limit is 40 hours
- **THEN** the scheduler checks 35 total hours against the 40-hour limit

#### Scenario: Exempt worker with no hour limit
- **WHEN** a per-diem worker has no `max_period_seconds` configured
- **THEN** the worker has no hour limit regardless of calendar or draft hours

### Requirement: Overtime check uses per-period hours
The `wouldBeOvertime` function SHALL use per-period hour totals (including calendar hours for standard workers) instead of per-week totals when determining whether an assignment would cause overtime.

#### Scenario: Overtime with calendar hours
- **WHEN** a standard worker has 38 hours committed in the calendar and 1 hour in the draft for the current weekly period
- **AND** the worker's per-period limit is 40 hours
- **AND** a 2-hour assignment is proposed
- **THEN** `wouldBeOvertime` returns True (39 + 2 = 41 > 40)

#### Scenario: No overtime without calendar hours for exempt worker
- **WHEN** an exempt worker has 38 hours committed in the calendar and 1 hour in the draft for the current weekly period
- **AND** the worker's per-period limit is 40 hours
- **AND** a 2-hour assignment is proposed
- **THEN** `wouldBeOvertime` returns False (only 1 + 2 = 3 draft hours counted against 40)

### Requirement: Scoring uses per-period remaining capacity
The scheduler scoring functions (`scoreShiftWorker`, `scoreSlotWorker`) SHALL compute remaining capacity based on per-period hours (including calendar hours for standard workers) rather than per-week hours.

#### Scenario: Capacity score reflects calendar hours
- **WHEN** a standard worker has 60 hours committed in the calendar for the current biweekly period
- **AND** the worker's per-period limit is 80 hours
- **THEN** the capacity score reflects 20 remaining hours, not 80

#### Scenario: Capacity score for exempt worker ignores calendar
- **WHEN** an exempt worker has 60 hours committed in the calendar for the current biweekly period
- **AND** has 5 hours in the draft
- **AND** the worker's per-period limit is 80 hours
- **THEN** the capacity score reflects 75 remaining hours (80 - 5 draft only)
