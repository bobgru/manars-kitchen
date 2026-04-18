# skill-create-guard Specification

## Purpose
Skill creation SHALL reject duplicate IDs with an informative error instead of silently performing an upsert. The current `INSERT OR REPLACE` behavior is replaced with an existence check followed by a plain `INSERT`.

## Requirements

### Requirement: Reject duplicate skill ID on create
The system SHALL check whether a skill with the given ID already exists before inserting. If it exists, the operation SHALL fail with an error message that names the existing skill and suggests using `skill rename`.

#### Scenario: Create succeeds for new ID
- **WHEN** `skill create 4 grill` is executed
- **AND** no skill with ID 4 exists
- **THEN** the skill is created with ID 4 and name "grill"

#### Scenario: Create fails for existing ID
- **WHEN** `skill create 4 pastry` is executed
- **AND** skill 4 already exists with name "grill"
- **THEN** the command fails with an error message: `Skill 4 already exists ("grill"). Use 'skill rename 4 <new-name>' to rename.`
- **AND** the existing skill is NOT modified

#### Scenario: RPC create rejects duplicate
- **WHEN** the RPC skill create endpoint is called with an ID that already exists
- **THEN** the request fails with an appropriate error response
- **AND** the existing skill is NOT modified

### Requirement: SQL uses INSERT instead of INSERT OR REPLACE
The `sqlCreateSkill` function SHALL use `INSERT INTO skills` (not `INSERT OR REPLACE`) and SHALL check for existence before inserting.

#### Scenario: No silent overwrite
- **WHEN** a skill with ID 4 exists
- **AND** `sqlCreateSkill` is called with ID 4
- **THEN** the existing row is unchanged and an error is raised
