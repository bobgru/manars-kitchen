## MODIFIED Requirements

### Requirement: classify function
The system SHALL provide `classify :: String -> CommandMeta` that extracts structured metadata from a raw command string.

The `schedule` entity type SHALL remain, as the entity type for the commands that
belong to no entity group — `help`, `quit`, `audit`, `replay`, `demo`, `use`,
`context`. There SHALL be no `schedule <op>`, `assign` or `unassign` grammar to
classify: those commands are removed with the named-schedule surface, and
`calendar commit` with them.

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
- **WHEN** classify is called with `"draft list"`
- **THEN** it returns CommandMeta with entityType="draft", operation="list", isMutation=False

#### Scenario: Group-less command keeps the schedule entity type
- **WHEN** classify is called with `"audit"`
- **THEN** it returns CommandMeta with entityType="schedule", operation="audit", isMutation=False

#### Scenario: Unknown command
- **WHEN** classify is called with `"foobar baz"`
- **THEN** it returns a default CommandMeta with all Maybe fields as Nothing and isMutation=False

#### Scenario: Variadic arguments captured in params
- **WHEN** classify is called with `"worker set-prefs 3 1 2 4"`
- **THEN** it returns CommandMeta with entityType="worker", operation="set-prefs", entityId=3, isMutation=True, and params contains the station ID list [1,2,4]

#### Scenario: Calendar commit is not a command
- **WHEN** classify is called with `"calendar commit week1 2026-04-06 2026-04-12 Initial schedule"`
- **THEN** it returns CommandMeta with entityType="calendar", operation="commit", isMutation=False,
  from the calendar catch-all arm, because no such subcommand exists to mutate anything

#### Scenario: Config commands
- **WHEN** classify is called with `"config set-pay-period biweekly 2026-04-06"`
- **THEN** it returns CommandMeta with entityType="config", operation="set-pay-period", isMutation=True

#### Scenario: What-if commands are not mutations
- **WHEN** classify is called with `"what-if grant-skill 3 5"`
- **THEN** it returns CommandMeta with entityType="what-if", operation="grant-skill", entityId=3, targetId=5, isMutation=False

#### Scenario: What-if apply is a mutation
- **WHEN** classify is called with `"what-if apply"`
- **THEN** it returns CommandMeta with entityType="what-if", operation="apply", isMutation=True
