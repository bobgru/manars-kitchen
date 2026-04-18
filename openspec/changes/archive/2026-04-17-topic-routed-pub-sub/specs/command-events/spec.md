# command-events Specification

## Purpose
Defines the `CommandEvent` payload type and the publishing pattern for domain mutations. Both CLI and RPC code paths build a `CommandEvent`, construct a topic via `buildTopic`, and publish to `busCommands`. This replaces the two separate inline audit log write paths with a single publish.

## Requirements

### Requirement: CommandEvent type
The system SHALL define a `CommandEvent` record with fields:
- `ceCommand :: String` — human-readable command text
- `ceMeta :: CommandMeta` — structured metadata from `classify`
- `ceSource :: Source` — origin of the event (`CLI` or `RPC`)
- `ceUsername :: String` — the authenticated user who triggered the command

#### Scenario: CLI-originated event
- **WHEN** a `CommandEvent` is built from a CLI command `"skill create 4 grill"` by user `"admin"`
- **THEN** `ceCommand` is `"skill create 4 grill"`, `ceSource` is `CLI`, `ceUsername` is `"admin"`, and `ceMeta` matches `classify "skill create 4 grill"`

#### Scenario: RPC-originated event
- **WHEN** a `CommandEvent` is built from an RPC handler for skill creation with ID 4 and name "grill"
- **THEN** `ceCommand` is `"skill create 4 grill"`, `ceSource` is `RPC`, and `ceMeta` matches `classify "skill create 4 grill"`

### Requirement: Source type
The system SHALL define `data Source = CLI | RPC | Demo` with `Eq` and `Show` instances. The `Demo` constructor is reserved for the future graphical demo feature; no code publishes with `Demo` in this change.

### Requirement: publishCommand helper
The system SHALL provide a helper function `publishCommand :: TopicBus CommandEvent -> Source -> String -> String -> IO ()` that takes a bus, source, username, and command string, then classifies the command, builds the topic, constructs the `CommandEvent`, and publishes it.

#### Scenario: publishCommand builds and publishes
- **WHEN** `publishCommand bus RPC "admin" "skill create 4 grill"` is called
- **AND** a subscriber is registered with pattern `"skill\\..*"`
- **THEN** the subscriber receives a `CommandEvent` with ceCommand="skill create 4 grill", ceSource=RPC, ceUsername="admin", and the topic is `"skill.create.4"`

### Requirement: CLI publishes mutating commands
The CLI REPL SHALL publish a `CommandEvent` on `busCommands` for every mutating command, replacing the inline `repoLogCommand` call.

#### Scenario: CLI mutation publishes event
- **WHEN** user "admin" enters `"skill create 4 grill"` in the CLI
- **AND** the command is mutating
- **THEN** a `CommandEvent` with ceSource=CLI and ceUsername="admin" is published to `busCommands` with topic `"skill.create.4"`

#### Scenario: CLI non-mutation does not publish
- **WHEN** user enters `"skill list"` in the CLI
- **THEN** no `CommandEvent` is published

### Requirement: RPC handlers publish command events
Each mutating RPC handler SHALL publish a `CommandEvent` on `busCommands`, replacing the inline `logRpc` call. Initially, only skill-related RPC handlers are migrated; others continue using `logRpc` until a follow-up change.

#### Scenario: RPC skill create publishes event
- **WHEN** the RPC handler for skill creation processes a request for skill ID 4 named "grill"
- **THEN** a `CommandEvent` with ceSource=RPC is published to `busCommands` with topic `"skill.create.4"`

### Requirement: AppState carries AppBus
The CLI's `AppState` record SHALL include an `asBus :: AppBus` field so the bus is available throughout the REPL loop and command handlers.

#### Scenario: Bus available in command handler
- **WHEN** a command handler runs
- **THEN** it can access `busCommands` and `busProgress` via `asBus` on the `AppState`
