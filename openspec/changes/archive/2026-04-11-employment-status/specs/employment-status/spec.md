## ADDED Requirements

### Requirement: Employment status decomposed into orthogonal properties
The system SHALL model worker employment status as three independent properties: overtime model, pay period tracking, and temporary flag. These properties SHALL be stored per worker and loaded into the WorkerContext for use by the scheduler and display.

#### Scenario: Worker with no employment record uses defaults
- **WHEN** a worker has no entry in the worker_employment table
- **THEN** the system SHALL treat them as overtime_model=eligible, pay_period_tracking=standard, is_temp=false

#### Scenario: Worker employment properties are independent
- **WHEN** a worker's overtime_model is set to manual-only
- **AND** their pay_period_tracking is set to standard
- **THEN** the overtime_model and pay_period_tracking SHALL be stored and retrieved independently

### Requirement: Overtime model controls automatic overtime assignment
The system SHALL support three overtime models per worker: `eligible`, `manual-only`, and `exempt`. The scheduler SHALL use the overtime model to determine whether a worker can be auto-assigned overtime during Phase 2 (overtime retry).

#### Scenario: Eligible worker receives auto-assigned overtime
- **WHEN** a worker has overtime_model=eligible
- **AND** the scheduler is in Phase 2 (overtime retry)
- **AND** the worker can fill an unfilled slot but it would exceed their weekly hours
- **THEN** the scheduler SHALL auto-assign the worker to that slot as overtime

#### Scenario: Manual-only worker is skipped for auto-assigned overtime
- **WHEN** a worker has overtime_model=manual-only
- **AND** the scheduler is in Phase 2 (overtime retry)
- **THEN** the scheduler SHALL NOT auto-assign overtime to that worker
- **AND** the worker SHALL remain available for manual assignment by a manager

#### Scenario: Exempt worker and overtime concept
- **WHEN** a worker has overtime_model=exempt
- **THEN** the overtime concept SHALL NOT apply to that worker
- **AND** the scheduler SHALL treat the worker as having no overtime constraint

### Requirement: Pay period tracking controls hour limit enforcement
The system SHALL support two pay period tracking modes: `standard` and `exempt`. Workers with `exempt` tracking SHALL have no weekly hour limit enforced by the scheduler.

#### Scenario: Standard tracking enforces weekly hour limit
- **WHEN** a worker has pay_period_tracking=standard
- **AND** the worker has a configured weekly hour limit
- **THEN** the scheduler SHALL enforce that limit when making assignments

#### Scenario: Exempt tracking bypasses weekly hour limit
- **WHEN** a worker has pay_period_tracking=exempt
- **AND** the worker has a configured weekly hour limit
- **THEN** the scheduler SHALL NOT enforce the weekly hour limit
- **AND** the worker SHALL be assignable regardless of accumulated weekly hours

#### Scenario: Exempt tracking with no hour limit configured
- **WHEN** a worker has pay_period_tracking=exempt
- **AND** the worker has no configured weekly hour limit
- **THEN** the scheduler behavior SHALL be the same as for any worker with no hour limit

### Requirement: Temporary worker flag
The system SHALL support an `is_temp` boolean flag per worker. This flag SHALL be informational only and SHALL NOT affect scheduling calculations.

#### Scenario: Temp flag is displayed but does not affect scheduling
- **WHEN** a worker has is_temp=true
- **THEN** the worker info display SHALL show the temp status
- **AND** the scheduler SHALL treat the worker identically to a non-temp worker with the same properties

### Requirement: Convenience command sets employment status presets
The system SHALL provide a `worker set-status <worker> <status>` command that sets decomposed properties according to predefined presets.

#### Scenario: Set status to salaried
- **WHEN** user runs `worker set-status <w> salaried`
- **THEN** the system SHALL set overtime_model=manual-only, pay_period_tracking=standard
- **AND** the system SHALL set the worker's weekly hour limit to 40 hours

#### Scenario: Set status to full-time
- **WHEN** user runs `worker set-status <w> full-time`
- **THEN** the system SHALL set overtime_model=eligible, pay_period_tracking=standard
- **AND** the system SHALL set the worker's weekly hour limit to 40 hours

#### Scenario: Set status to part-time
- **WHEN** user runs `worker set-status <w> part-time`
- **THEN** the system SHALL set overtime_model=eligible, pay_period_tracking=standard
- **AND** the system SHALL NOT change the worker's weekly hour limit
- **AND** the system SHALL display a reminder to set hours with `worker set-hours`

#### Scenario: Set status to per-diem
- **WHEN** user runs `worker set-status <w> per-diem`
- **THEN** the system SHALL set overtime_model=exempt, pay_period_tracking=exempt
- **AND** the system SHALL remove the worker's weekly hour limit

### Requirement: Direct property commands for fine-grained control
The system SHALL provide commands to set individual employment properties: `worker set-overtime-model <w> eligible|manual-only|exempt`, `worker set-pay-tracking <w> standard|exempt`, and `worker set-temp <w> on|off`.

#### Scenario: Set overtime model directly
- **WHEN** user runs `worker set-overtime-model <w> manual-only`
- **THEN** the system SHALL set only the overtime_model property to manual-only
- **AND** other employment properties SHALL remain unchanged

#### Scenario: Set pay period tracking directly
- **WHEN** user runs `worker set-pay-tracking <w> exempt`
- **THEN** the system SHALL set only the pay_period_tracking property to exempt
- **AND** other employment properties SHALL remain unchanged

#### Scenario: Set temp flag directly
- **WHEN** user runs `worker set-temp <w> on`
- **THEN** the system SHALL set the is_temp flag to true
- **AND** other employment properties SHALL remain unchanged

### Requirement: Existing set-overtime command reinterpreted
The existing `worker set-overtime <w> on|off` command SHALL be reinterpreted through the employment model. For non-salaried workers, it SHALL set overtime_model to eligible (on) or back to the default (off). For salaried workers (overtime_model=manual-only), the command SHALL be a no-op and display a warning.

#### Scenario: Set overtime on for hourly worker
- **WHEN** user runs `worker set-overtime <w> on`
- **AND** the worker's overtime_model is not manual-only
- **THEN** the system SHALL set overtime_model to eligible

#### Scenario: Set overtime off for hourly worker
- **WHEN** user runs `worker set-overtime <w> off`
- **AND** the worker's overtime_model is not manual-only
- **THEN** the system SHALL set overtime_model to eligible but remove the worker from the overtime opt-in set (backward compatible behavior)

#### Scenario: Set overtime for salaried worker warns
- **WHEN** user runs `worker set-overtime <w> on` or `worker set-overtime <w> off`
- **AND** the worker's overtime_model is manual-only
- **THEN** the system SHALL display a warning that salaried workers always use manual-only overtime
- **AND** the overtime_model SHALL remain manual-only

### Requirement: Worker info displays employment status
The `worker info` command SHALL display each worker's employment status properties alongside existing information.

#### Scenario: Worker info shows employment status
- **WHEN** user runs `worker info`
- **THEN** for each worker, the display SHALL include overtime model, pay period tracking, and temp flag
- **AND** workers with default values (eligible, standard, not temp) SHALL show those defaults

#### Scenario: Worker info shows non-default employment status
- **WHEN** a worker has overtime_model=manual-only and is_temp=true
- **AND** user runs `worker info`
- **THEN** the display SHALL show "manual-only" for overtime model and "temp" flag

### Requirement: Database storage for employment properties
The system SHALL store employment properties in a `worker_employment` table with worker_id as primary key, overtime_model as TEXT with CHECK constraint, pay_period_tracking as TEXT with CHECK constraint, and is_temp as BOOLEAN.

#### Scenario: Employment record persists across restarts
- **WHEN** a worker's employment status is set
- **AND** the system is restarted
- **THEN** the employment properties SHALL be loaded from the database and reflected in the WorkerContext

#### Scenario: Employment record created on first property set
- **WHEN** a worker has no employment record
- **AND** any employment property is set for that worker
- **THEN** the system SHALL create a record with the specified property and defaults for other properties
