## MODIFIED Requirements

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
