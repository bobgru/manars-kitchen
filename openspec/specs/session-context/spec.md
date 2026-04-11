## ADDED Requirements

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

### Requirement: Dot placeholder substitutes current context
The system SHALL replace a `"."` argument with the current context value for the expected entity type at that argument position. If no context is set for the required entity type, the system SHALL display an error indicating which context is missing. This SHALL apply to all command groups including `what-if` commands, where argument positions map to entity kinds as follows: worker positions resolve from worker context, station positions from station context, and skill positions from skill context.

#### Scenario: Dot substitution for worker and skill
- **WHEN** worker context is set to "marco" (ID 2) and skill context is set to "grill" (ID 1)
- **AND** user types `worker grant-skill . .`
- **THEN** system resolves the first `.` to worker ID 2 and the second `.` to skill ID 1, executing `worker grant-skill 2 1`

#### Scenario: Dot with missing context
- **WHEN** no worker context is set
- **AND** user types `worker set-hours . 40`
- **THEN** system displays "No worker context set. Use 'use worker <name>' first."

#### Scenario: Dot mixed with explicit values
- **WHEN** worker context is set to "marco" (ID 2)
- **AND** user types `worker grant-skill . 3`
- **THEN** system resolves `.` to worker ID 2 and uses 3 as the skill ID

#### Scenario: Dot substitution in what-if grant-skill
- **WHEN** worker context is set to "carol" (ID 3) and skill context is set to "cooking" (ID 2)
- **AND** user types `what-if grant-skill . .`
- **THEN** system resolves the first `.` to worker ID 3 and the second `.` to skill ID 2, adding a GrantSkill hint

#### Scenario: Dot substitution in what-if pin
- **WHEN** worker context is set to "marco" (ID 2) and station context is set to "grill" (ID 1)
- **AND** user types `what-if pin . . 2026-04-06 9`
- **THEN** system resolves the first `.` to worker ID 2 and the second `.` to station ID 1, adding a PinAssignment hint

#### Scenario: Dot substitution in what-if waive-overtime
- **WHEN** worker context is set to "bob" (ID 2)
- **AND** user types `what-if waive-overtime .`
- **THEN** system resolves `.` to worker ID 2, adding a WaiveOvertime hint

### Requirement: View current context
The system SHALL display all currently set contexts when the user types `context view`. If no contexts are set, it SHALL indicate that.

#### Scenario: View with active contexts
- **WHEN** worker context is "marco" (ID 2) and skill context is "grill" (ID 1)
- **AND** user types `context view`
- **THEN** system displays:
  ```
  Current context:
    worker: marco (ID 2)
    skill: grill (ID 1)
  ```

#### Scenario: View with no contexts
- **WHEN** no contexts are set
- **AND** user types `context view`
- **THEN** system displays "No context set."

### Requirement: Clear context
The system SHALL clear all contexts when the user types `context clear`. The system SHALL clear a single entity type's context when the user types `context clear <entity-type>`.

#### Scenario: Clear all contexts
- **WHEN** user types `context clear`
- **THEN** all session contexts are removed, and system confirms "Context cleared."

#### Scenario: Clear specific context
- **WHEN** user types `context clear worker`
- **THEN** only the worker context is removed; other contexts remain

#### Scenario: Unfrozen date ranges tracked in session
- **WHEN** user runs `calendar unfreeze 2026-04-01 2026-04-03`
- **THEN** the range (2026-04-01, 2026-04-03) is added to the session's set of unfrozen ranges
- **AND** this state is accessible to the draft creation flow for freeze-line checks

#### Scenario: Unfrozen ranges cleared on commit
- **WHEN** a draft is committed that touched historical dates
- **THEN** the session's set of unfrozen ranges is reset to empty
