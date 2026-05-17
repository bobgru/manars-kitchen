# Pin Name Args

`pin` / `unpin` CLI commands and their REST endpoints take worker name and station name.

## Requirements

### Requirement: pin and unpin take worker name and station name
The system SHALL accept worker names and station names for `pin` and `unpin` CLI commands. Numeric ids SHALL still be accepted.

#### Scenario: pin by worker and station name
- **WHEN** an admin runs `pin alice grill monday 9`
- **THEN** the system resolves `alice` to a `WorkerId` and `grill` to a `StationId`, and stores the pinned assignment

#### Scenario: pin with shift name
- **WHEN** an admin runs `pin alice grill monday morning`
- **THEN** the system resolves names and stores a shift-based pin

#### Scenario: unpin by names
- **WHEN** an admin runs `unpin alice grill monday 9`
- **THEN** the matching pinned assignment is removed

#### Scenario: numeric ids still work
- **WHEN** an admin runs `pin 2 1 monday 9`
- **THEN** the system interprets numeric strings as ids and stores the pin

#### Scenario: unknown worker name on pin
- **WHEN** an admin runs `pin ghost grill monday 9`
- **THEN** the system reports "not found" and makes no change
