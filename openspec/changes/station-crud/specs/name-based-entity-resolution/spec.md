## MODIFIED Requirements

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

#### Scenario: Station commands use new verbs
- **WHEN** user types `station delete "Grill"`
- **THEN** system resolves "Grill" to the station ID and deletes the station

#### Scenario: Station rename resolution
- **WHEN** user types `station rename "Grill" "Main Grill"`
- **THEN** system resolves "Grill" to the station ID; "Main Grill" is passed through as the new name (not resolved)
