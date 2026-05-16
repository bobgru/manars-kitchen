## ADDED Requirements

### Requirement: Entity arguments accept names or IDs
The system SHALL accept entity names in addition to numeric IDs for all command arguments that reference workers, skills, stations, or absence types. Numeric IDs SHALL continue to work as before. The system SHALL resolve names to IDs before executing the command.

Station commands SHALL use the following verb names:
- `station create` (formerly `station add`)
- `station delete` (formerly `station remove`)
- `station force-delete` (new)
- `station rename` (new)
- `station view` (new)

The resolver's `commandEntityMap` SHALL be updated to use the new verb names.

#### Scenario: Worker referenced by name
- **WHEN** user types `worker grant-skill marco grill`
- **THEN** system resolves "marco" to the worker ID and "grill" to the skill ID, and grants the skill

#### Scenario: Worker referenced by numeric ID
- **WHEN** user types `worker grant-skill 2 1`
- **THEN** system resolves IDs as before and grants the skill

#### Scenario: Mixed name and ID references
- **WHEN** user types `worker grant-skill marco 1`
- **THEN** system resolves "marco" by name and uses 1 as a numeric skill ID

#### Scenario: Station commands use new verbs
- **WHEN** user types `station delete "Grill"`
- **THEN** system resolves "Grill" to the station ID and deletes the station

#### Scenario: Station rename resolution
- **WHEN** user types `station rename "Grill" "Main Grill"`
- **THEN** system resolves "Grill" to the station ID; "Main Grill" is passed through as the new name (not resolved)

### Requirement: Name resolution is case-insensitive
The system SHALL resolve entity names case-insensitively. If the user types "Marco", "marco", or "MARCO", all SHALL resolve to the same worker.

#### Scenario: Case-insensitive worker name
- **WHEN** user types `worker set-hours Marco 40`
- **THEN** system resolves "Marco" to the worker whose username matches case-insensitively

### Requirement: Ambiguous or unknown names produce clear errors
The system SHALL display a clear error message when a name cannot be resolved to an entity. The error SHALL state the entity type and the name that failed to resolve.

#### Scenario: Unknown entity name
- **WHEN** user types `worker grant-skill unknown-name grill`
- **THEN** system displays "Unknown worker: unknown-name"

#### Scenario: Name is valid integer but no entity exists
- **WHEN** user types `worker set-hours 999 40` and no worker with ID 999 exists
- **THEN** system proceeds with ID 999 (existing behavior preserved; downstream handler reports the error)

### Requirement: Numeric input always preferred as ID
When an argument could be interpreted as both a name and an ID (e.g., a worker named "1"), the system SHALL interpret numeric strings as IDs. Name lookup SHALL only occur for non-numeric strings.

#### Scenario: Numeric string interpreted as ID
- **WHEN** user types `worker set-hours 2 40`
- **THEN** system interprets "2" as worker ID 2, not as a name lookup
