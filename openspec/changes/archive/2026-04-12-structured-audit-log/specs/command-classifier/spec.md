## ADDED Requirements

### Requirement: CommandMeta type
The system SHALL define a `CommandMeta` record with fields: `cmEntityType` (Maybe String), `cmOperation` (Maybe String), `cmEntityId` (Maybe Int), `cmTargetId` (Maybe Int), `cmDateFrom` (Maybe Day), `cmDateTo` (Maybe Day), `cmIsMutation` (Bool), `cmParams` (Maybe Value for JSON blob).

#### Scenario: Default metadata
- **WHEN** a CommandMeta is constructed with `defaultMeta`
- **THEN** all Maybe fields are Nothing and cmIsMutation is False

### Requirement: classify function
The system SHALL provide `classify :: String -> CommandMeta` that extracts structured metadata from a raw command string.

#### Scenario: Single-entity mutating command
- **WHEN** classify is called with `"station add 1 grill"`
- **THEN** it returns CommandMeta with entityType="station", operation="add", entityId=1, isMutation=True

#### Scenario: Two-entity mutating command
- **WHEN** classify is called with `"worker grant-skill 3 5"`
- **THEN** it returns CommandMeta with entityType="worker", operation="grant-skill", entityId=3, targetId=5, isMutation=True

#### Scenario: Command with date range
- **WHEN** classify is called with `"draft create 2026-04-13 2026-04-19"`
- **THEN** it returns CommandMeta with entityType="draft", operation="create", dateFrom=2026-04-13, dateTo=2026-04-19, isMutation=True

#### Scenario: Command with single date
- **WHEN** classify is called with `"absence request 1 3 2026-04-10 2026-04-10"`
- **THEN** it returns CommandMeta with entityType="absence", operation="request", entityId=1, targetId=3, dateFrom=2026-04-10, dateTo=2026-04-10, isMutation=True

#### Scenario: Non-mutating command
- **WHEN** classify is called with `"schedule list"`
- **THEN** it returns CommandMeta with entityType="schedule", operation="list", isMutation=False

#### Scenario: Unknown command
- **WHEN** classify is called with `"foobar baz"`
- **THEN** it returns a default CommandMeta with all Maybe fields as Nothing and isMutation=False

#### Scenario: Variadic arguments captured in params
- **WHEN** classify is called with `"worker set-prefs 3 1 2 4"`
- **THEN** it returns CommandMeta with entityType="worker", operation="set-prefs", entityId=3, isMutation=True, and params contains the station ID list [1,2,4]

#### Scenario: Calendar commit with note
- **WHEN** classify is called with `"calendar commit week1 2026-04-06 2026-04-12 Initial schedule"`
- **THEN** it returns CommandMeta with entityType="calendar", operation="commit", dateFrom=2026-04-06, dateTo=2026-04-12, isMutation=True

#### Scenario: Config commands
- **WHEN** classify is called with `"config set-pay-period biweekly 2026-04-06"`
- **THEN** it returns CommandMeta with entityType="config", operation="set-pay-period", isMutation=True

#### Scenario: What-if commands are not mutations
- **WHEN** classify is called with `"what-if grant-skill 3 5"`
- **THEN** it returns CommandMeta with entityType="what-if", operation="grant-skill", entityId=3, targetId=5, isMutation=False

#### Scenario: What-if apply is a mutation
- **WHEN** classify is called with `"what-if apply"`
- **THEN** it returns CommandMeta with entityType="what-if", operation="apply", isMutation=True

### Requirement: render function
The system SHALL provide `render :: CommandMeta -> String` that produces a human-readable command string from structured metadata.

#### Scenario: Round-trip for a simple command
- **WHEN** classify is called with `"station add 1 grill"` and the result is passed to render
- **THEN** render produces `"station add 1 grill"` (or a normalized equivalent)

#### Scenario: Round-trip for a two-entity command
- **WHEN** classify is called with `"worker grant-skill 3 5"` and the result is passed to render
- **THEN** render produces `"worker grant-skill 3 5"`

#### Scenario: Render from REST-originated metadata
- **WHEN** render is called with CommandMeta{entityType="worker", operation="grant-skill", entityId=3, targetId=5}
- **THEN** it produces `"worker grant-skill 3 5"`

#### Scenario: Render with date range
- **WHEN** render is called with CommandMeta{entityType="draft", operation="create", dateFrom=2026-04-13, dateTo=2026-04-19}
- **THEN** it produces `"draft create 2026-04-13 2026-04-19"`

### Requirement: isMutation consistency
The system SHALL ensure that `cmIsMutation (classify cmd)` agrees with `isMutating (parseCommand cmd)` for all valid command strings.

#### Scenario: Property test
- **WHEN** any command string is both parsed with `parseCommand` and classified with `classify`
- **THEN** `cmIsMutation` matches `isMutating`

### Requirement: classify coverage
The system SHALL ensure that for every command string where `isMutating (parseCommand cmd)` is True, `classify cmd` produces a CommandMeta where `cmEntityType` is not Nothing.

#### Scenario: No mutating command goes unclassified
- **WHEN** any mutating command is classified
- **THEN** cmEntityType is Just (some entity type string)
