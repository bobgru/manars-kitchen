## MODIFIED Requirements

### Requirement: REST handlers publish as GUI source
All mutating REST handlers SHALL publish a `CommandEvent` to the `busCommands` channel with `ceSource == GUI`. The event SHALL include the authenticated user's username and session ID.

This SHALL include draft creation and draft generation, which previously published
nothing — the two operations that change a draft the most were invisible to the
audit log, the terminal pane and the event stream.

#### Scenario: Skill creation via REST
- **WHEN** a user creates a skill via `POST /api/skills`
- **THEN** a `CommandEvent` is published with `ceSource == GUI`, the user's username, and the user's session ID

#### Scenario: Implication toggle via REST
- **WHEN** a user adds a skill implication via the REST API
- **THEN** a `CommandEvent` is published with `ceSource == GUI`

#### Scenario: Draft creation via REST
- **WHEN** a user creates a draft via `POST /api/drafts` for 2026-09-07 to 2026-09-13
- **THEN** a `CommandEvent` is published with the command string `draft create 2026-09-07 2026-09-13`

#### Scenario: Draft generation via REST
- **WHEN** a user generates draft 1 via `POST /api/drafts/1/generate`
- **THEN** a `CommandEvent` is published with the command string `draft generate 1`

#### Scenario: A refused draft creation publishes nothing
- **WHEN** `POST /api/drafts` is refused with 409 because the range covers frozen dates
- **THEN** no `CommandEvent` is published
