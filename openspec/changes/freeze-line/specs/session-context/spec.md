## MODIFIED Requirements

### Requirement: Set entity context with use command
The system SHALL allow users to set a session context for an entity type using `use <entity-type> <name-or-id>`. Supported entity types SHALL be: `worker`, `skill`, `station`, `absence-type`. The context SHALL persist for the duration of the REPL session.

The session state SHALL also track a set of temporarily unfrozen date ranges (as `(Day, Day)` pairs), managed by the `calendar unfreeze` and draft commit flows. This state SHALL be stored in an `IORef` in `AppState` and SHALL be cleared on process restart.

#### Scenario: Set worker context by name
- **WHEN** user types `use worker marco`
- **THEN** system resolves "marco" to a worker ID and stores it as the active worker context, confirming: "Context set: worker = marco (ID 2)"

#### Scenario: Set station context by ID
- **WHEN** user types `use station 1`
- **THEN** system stores station ID 1 as the active station context, confirming with the station name

#### Scenario: Set context with invalid entity type
- **WHEN** user types `use schedule foo`
- **THEN** system displays an error listing valid entity types

#### Scenario: Set context with unknown name
- **WHEN** user types `use worker nobody`
- **THEN** system displays "Unknown worker: nobody"

#### Scenario: Unfrozen date ranges tracked in session
- **WHEN** user runs `calendar unfreeze 2026-04-01 2026-04-03`
- **THEN** the range (2026-04-01, 2026-04-03) is added to the session's set of unfrozen ranges
- **AND** this state is accessible to the draft creation flow for freeze-line checks

#### Scenario: Unfrozen ranges cleared on commit
- **WHEN** a draft is committed that touched historical dates
- **THEN** the session's set of unfrozen ranges is reset to empty
