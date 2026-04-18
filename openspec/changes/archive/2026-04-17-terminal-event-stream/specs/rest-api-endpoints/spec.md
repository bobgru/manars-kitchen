## MODIFIED Requirements

### Requirement: All protected endpoints receive authenticated user
Every REST endpoint (except `POST /api/login`) SHALL receive the authenticated `User` value resolved by the auth middleware. Handler functions SHALL accept `User` as their first parameter.

#### Scenario: Handler has access to user identity
- **WHEN** an authenticated request is made to any protected endpoint
- **THEN** the handler receives the full `User` record including `userId`, `userRole`, and `userWorkerId`

## ADDED Requirements

### Requirement: REST handlers publish as GUI source
All mutating REST handlers SHALL publish a `CommandEvent` to the `busCommands` channel with `ceSource == GUI`. The event SHALL include the authenticated user's username and session ID.

#### Scenario: Skill creation via REST
- **WHEN** a user creates a skill via `POST /api/skills`
- **THEN** a `CommandEvent` is published with `ceSource == GUI`, the user's username, and the user's session ID

#### Scenario: Implication toggle via REST
- **WHEN** a user adds a skill implication via the REST API
- **THEN** a `CommandEvent` is published with `ceSource == GUI`

### Requirement: Name-based command strings
REST handlers SHALL publish command strings that use entity names instead of numeric IDs. Before publishing, handlers SHALL look up entity names from the repository. These lookups SHALL happen before the mutation so that the name is available even for delete operations.

#### Scenario: Skill rename uses names
- **WHEN** the user renames skill ID 1 (currently named "grill") to "broiler" via REST
- **THEN** the published command string is `skill rename grill broiler`

#### Scenario: Skill delete uses name
- **WHEN** the user deletes skill ID 1 (named "grill") via REST
- **THEN** the published command string is `skill delete grill`

#### Scenario: Worker skill grant uses names
- **WHEN** the user grants skill ID 2 ("pastry") to worker ID 3 ("marco") via REST
- **THEN** the published command string is `worker grant-skill marco pastry`

#### Scenario: Pin assignment uses names
- **WHEN** the user pins worker "marco" to station "grill" via REST
- **THEN** the published command string is `pin add marco grill`

#### Scenario: Name lookup before delete
- **WHEN** the user deletes a skill via REST
- **THEN** the handler looks up the skill name BEFORE executing the deletion
- **AND** uses the name in the published command string
