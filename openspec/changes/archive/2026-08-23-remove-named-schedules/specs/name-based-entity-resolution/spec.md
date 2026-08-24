## MODIFIED Requirements

### Requirement: Entity arguments accept names or IDs
The system SHALL accept entity names in addition to numeric IDs for all command arguments that reference workers, skills, stations, or absence types. Numeric IDs SHALL continue to work as before. The system SHALL resolve names to IDs before executing the command. After this change, **every** command that references a worker accepts a worker name; previously this was true for many but not all worker verbs.

Station commands SHALL use the following verb names (unchanged from the prior version):
- `station create` (formerly `station add`)
- `station delete` (formerly `station remove`)
- `station force-delete`
- `station rename`
- `station view`

Worker resolution SHALL delegate to `Service.Worker.resolveWorkerByName`, which distinguishes three error categories: (1) user not found, (2) user exists but `worker_status = 'none'` (not a worker), (3) user is a worker (active or inactive). The resolver's `commandEntityMap` SHALL list all worker-keyed verbs:
`worker grant-skill`, `worker revoke-skill`, `worker set-hours`, `worker set-overtime`, `worker set-prefs`, `worker set-shift-pref`, `worker set-variety`, `worker set-weekend-only`, `worker set-status`, `worker set-overtime-model`, `worker set-pay-tracking`, `worker set-temp`, `worker set-seniority`, `worker set-cross-training`, `worker clear-cross-training`, `worker avoid-pairing`, `worker clear-avoid-pairing`, `worker prefer-pairing`, `worker clear-prefer-pairing`, `worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`, `pin`, `unpin`, and the worker-referencing `what-if` verbs.

`assign` and `unassign` are no longer on that list: the commands are removed with
the named-schedule surface.

#### Scenario: Worker referenced by name
- **WHEN** user types `worker grant-skill marco grill`
- **THEN** system resolves "marco" to the worker ID and "grill" to the skill ID, and grants the skill
