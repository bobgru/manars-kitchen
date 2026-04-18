## ADDED Requirements

### Requirement: SkillId used in CLI command ADT

All `Command` variants that reference a skill ID SHALL use `SkillId` instead of raw `Int`.

#### Scenario: Command variants use SkillId

- **WHEN** inspecting the Command ADT in Commands.hs
- **THEN** `SkillCreate`, `SkillRename`, `SkillDelete`, `SkillForceDelete`, `SkillView`, `SkillImplication`, `SkillRemoveImplication`, and any other skill-referencing variants use `SkillId` as the parameter type

### Requirement: SkillId used in Servant API captures

All Servant API route captures for skill IDs SHALL use `Capture "id" SkillId` with `FromHttpApiData` and `ToHttpApiData` instances.

#### Scenario: Server compiles with SkillId captures

- **WHEN** `Server/Api.hs` uses `Capture "id" SkillId` for skill routes
- **THEN** the server compiles and correctly parses integer URL segments into `SkillId` values

#### Scenario: Handler functions receive SkillId

- **WHEN** inspecting skill-related handler functions in `Server/Handlers.hs`
- **THEN** parameters that represent skill IDs have type `SkillId`, not `Int`

### Requirement: FromHttpApiData and ToHttpApiData instances for SkillId

`SkillId` SHALL have `FromHttpApiData` and `ToHttpApiData` instances that parse/render as plain integers.

#### Scenario: Parse valid skill ID from URL

- **WHEN** a request arrives at `/api/skills/42`
- **THEN** Servant parses "42" into `SkillId 42`

#### Scenario: Reject non-integer skill ID in URL

- **WHEN** a request arrives at `/api/skills/abc`
- **THEN** Servant returns a 400 error
