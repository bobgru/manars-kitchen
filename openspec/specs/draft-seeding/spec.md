## ADDED Requirements

### Requirement: Seed draft from calendar and pins
When a draft is created for a date range, the system SHALL seed it by loading the existing calendar assignments for that range and expanding pins into the range's slots, then merging the two with pin precedence.

#### Scenario: Seed from calendar only (no pins)
- **WHEN** a draft is created for Apr 1-30 and no pins exist
- **THEN** the draft's initial assignments match the calendar assignments for Apr 1-30

#### Scenario: Seed from pins only (empty calendar)
- **WHEN** a draft is created for Apr 1-30, the calendar is empty for that range, and pins exist
- **THEN** the draft's initial assignments are the pins expanded into Apr 1-30

#### Scenario: Seed merge with pin precedence
- **WHEN** a draft is created for Apr 1-30, the calendar has Worker 3 at Station 2 on Monday Apr 6 at 9:00, and a pin says Worker 3 is at Station 1 on Mondays at 9:00
- **THEN** the draft's initial assignment for Worker 3 on Apr 6 at 9:00 is Station 1 (pin wins)
- **AND** all other calendar assignments for the range are preserved

#### Scenario: Seed with no conflicts
- **WHEN** calendar assignments and pin expansions do not conflict (different workers or different slots)
- **THEN** the draft contains the union of both

#### Scenario: Seed empty range
- **WHEN** a draft is created for a date range with no calendar data and no applicable pins
- **THEN** the draft starts with no assignments

### Requirement: Pin expansion uses active shift definitions
When expanding pins for draft seeding, the system SHALL use the currently configured shift definitions (from `repoLoadShifts`), falling back to default shifts if none are configured. This is the same behavior as `Service/Schedule.hs`.

#### Scenario: Shift-level pin expanded during seeding
- **WHEN** a pin specifies Worker 1 at Station 1 on Mondays for the "morning" shift
- **THEN** the draft is seeded with Worker 1 at Station 1 for each morning-shift hour on every Monday in the date range

### Requirement: Conflict resolution key
A conflict between a calendar assignment and a pin-expanded assignment is identified by matching worker_id + slot_date + slot_start. When a conflict exists, the pin-expanded assignment (including its station) replaces the calendar assignment.

#### Scenario: Same worker, same slot, different station
- **WHEN** the calendar has Assignment(Worker 1, Station 2, Monday 9:00) and a pin expands to Assignment(Worker 1, Station 1, Monday 9:00)
- **THEN** the draft contains Assignment(Worker 1, Station 1, Monday 9:00) -- pin wins

#### Scenario: Same station, same slot, different worker -- no conflict
- **WHEN** the calendar has Assignment(Worker 1, Station 1, Monday 9:00) and a pin expands to Assignment(Worker 2, Station 1, Monday 9:00)
- **THEN** the draft contains both assignments (no conflict on worker+slot key)

### Requirement: Slot list generation for date range
The seeding process SHALL generate the full slot list for the draft's date range using the configured shift definitions. This slot list is used both for pin expansion and as the set of available slots for subsequent `draft generate` calls.

#### Scenario: Slot list covers full date range
- **WHEN** a draft is created for Apr 1-7 with shifts defining hours 6:00-22:00
- **THEN** the slot list includes one slot per hour per day for Apr 1 through Apr 7
