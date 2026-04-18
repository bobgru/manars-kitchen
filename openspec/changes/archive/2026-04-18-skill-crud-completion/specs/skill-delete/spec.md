## ADDED Requirements

### Requirement: Safe skill deletion via CLI

The system SHALL provide a `skill delete <id>` command that deletes a skill only if it has no references in any related table (skill_implications, worker_skills, station_required_skills, worker_cross_training). If references exist, the command SHALL print an error listing all references grouped by type.

#### Scenario: Delete unreferenced skill

- **WHEN** user runs `skill delete <id>` for a skill with no references
- **THEN** the skill is removed from the skills table and the command prints a confirmation message

#### Scenario: Delete referenced skill

- **WHEN** user runs `skill delete <id>` for a skill referenced by workers, stations, implications, or cross-training goals
- **THEN** the command prints an error listing each reference (e.g., "Worker 2 (Alice) has this skill", "Station 1 (Grill) requires this skill") and the skill is NOT deleted

#### Scenario: Delete nonexistent skill

- **WHEN** user runs `skill delete <id>` for an ID that does not exist
- **THEN** the command prints an error indicating the skill was not found

### Requirement: Force skill deletion via CLI

The system SHALL provide a `skill force-delete <id>` command that removes all references to a skill by dispatching individual CLI commands through the full command pipeline, then deletes the skill itself.

#### Scenario: Force-delete skill with references

- **WHEN** user runs `skill force-delete <id>` for a skill referenced by 2 workers, 1 station, 1 cross-training goal, and 2 implications
- **THEN** the system dispatches `worker revoke-skill` for each worker, `station remove-required-skill` for each station, `worker clear-cross-training` for each cross-training goal, and `skill remove-implication` for each implication, each producing its own audit log entry, followed by `skill delete` to remove the now-unreferenced skill

#### Scenario: Force-delete unreferenced skill

- **WHEN** user runs `skill force-delete <id>` for a skill with no references
- **THEN** the system dispatches only `skill delete` (no removal commands needed)

#### Scenario: Each sub-command is audited independently

- **WHEN** a force-delete removes 3 references and then the skill itself
- **THEN** the audit log contains 4 entries: one for each reference removal command and one for the skill deletion

### Requirement: Safe skill deletion via API

The system SHALL provide `DELETE /api/skills/:id` that attempts safe deletion. On success it returns 200. If references exist it returns 409 with a JSON body listing references by type (workers, stations, implications, cross-training).

#### Scenario: API safe delete succeeds

- **WHEN** `DELETE /api/skills/:id` is called for an unreferenced skill
- **THEN** the response status is 200 and the skill is deleted

#### Scenario: API safe delete blocked

- **WHEN** `DELETE /api/skills/:id` is called for a referenced skill
- **THEN** the response status is 409 and the body contains a JSON object with arrays of references: workers (id + name), stations (id + name), implications (id + name), cross-training (id + name)

### Requirement: Force skill deletion via API

The system SHALL provide `DELETE /api/skills/:id/force` that removes all references and deletes the skill, dispatching individual commands through the command pipeline.

#### Scenario: API force delete

- **WHEN** `DELETE /api/skills/:id/force` is called
- **THEN** all references are removed via individual commands, the skill is deleted, and the response status is 200

### Requirement: Skill delete commands require admin

Both `skill delete` and `skill force-delete` SHALL require admin privileges.

#### Scenario: Non-admin attempts delete

- **WHEN** a non-admin user runs `skill delete <id>` or `skill force-delete <id>`
- **THEN** the command is rejected with a permission error
