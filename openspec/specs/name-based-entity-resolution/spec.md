## ADDED Requirements

### Requirement: Entity arguments accept names or IDs
The system SHALL accept entity names in addition to numeric IDs for all command arguments that reference workers, skills, stations, or absence types. Numeric IDs SHALL continue to work as before. The system SHALL resolve names to IDs before executing the command. After this change, **every** command that references a worker accepts a worker name; previously this was true for many but not all worker verbs.

Station commands SHALL use the following verb names (unchanged from the prior version):
- `station create` (formerly `station add`)
- `station delete` (formerly `station remove`)
- `station force-delete`
- `station rename`
- `station view`

Worker resolution SHALL delegate to `Service.Worker.resolveWorkerByName`, which distinguishes three error categories: (1) user not found, (2) user exists but `worker_status = 'none'` (not a worker), (3) user is a worker (active or inactive). The resolver's `commandEntityMap` SHALL list all worker-keyed verbs:
`worker grant-skill`, `worker revoke-skill`, `worker set-hours`, `worker set-overtime`, `worker set-prefs`, `worker set-shift-pref`, `worker set-variety`, `worker set-weekend-only`, `worker set-status`, `worker set-overtime-model`, `worker set-pay-tracking`, `worker set-temp`, `worker set-seniority`, `worker set-cross-training`, `worker clear-cross-training`, `worker avoid-pairing`, `worker clear-avoid-pairing`, `worker prefer-pairing`, `worker clear-prefer-pairing`, `worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`, `pin`, `unpin`, `assign`, `unassign`, and the worker-referencing `what-if` verbs.

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

#### Scenario: Worker resolver distinguishes "not a worker"
- **WHEN** user types `worker set-hours admin-only 40` and `admin-only` is a user with `worker_status = 'none'`
- **THEN** system displays a "not a worker" error distinct from "not found"

#### Scenario: Worker resolver permits inactive workers
- **WHEN** user types `worker set-hours alice 40` and alice's status is `inactive`
- **THEN** system resolves alice and updates her stored hours; she remains inactive

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
