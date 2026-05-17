# Assign Name Args

`schedule assign` / `schedule unassign` CLI commands take worker name and station name.

## Requirements

### Requirement: schedule assign and unassign take worker and station names
The system SHALL accept worker names and station names for the `assign` and `unassign` CLI commands. The schedule name remains a string. Date and hour remain as before. Numeric ids SHALL still be accepted.

#### Scenario: assign by names
- **WHEN** an admin runs `assign april alice grill 2026-04-06 9`
- **THEN** the system resolves `alice` to a `WorkerId` and `grill` to a `StationId`, and assigns the worker to the slot in schedule `april`

#### Scenario: unassign by names
- **WHEN** an admin runs `unassign april alice grill 2026-04-06 9`
- **THEN** the matching assignment is removed from schedule `april`

#### Scenario: numeric ids still work
- **WHEN** an admin runs `assign april 2 1 2026-04-06 9`
- **THEN** the system interprets numeric strings as ids and proceeds

#### Scenario: not-a-worker on assign
- **WHEN** an admin runs `assign april admin-only grill 2026-04-06 9` and `admin-only` has `worker_status = 'none'`
- **THEN** the system reports "not a worker" and makes no change
