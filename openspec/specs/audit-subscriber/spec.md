# audit-subscriber Specification

## Purpose
The audit log writer becomes a subscriber on `busCommands` instead of being called inline. A single subscriber handles both CLI and RPC-originated events, writing to the `audit_log` table with the same structured fields as before.

## Requirements

### Requirement: Audit subscriber registration
The system SHALL provide `registerAuditSubscriber :: TopicBus CommandEvent -> Repository -> IO SubscriptionId` that subscribes to all command events (pattern `".*"`) and writes each to the audit log.

#### Scenario: Audit subscriber logs CLI event
- **WHEN** the audit subscriber is registered
- **AND** a CLI-originated `CommandEvent` is published for `"skill create 4 grill"` by user `"admin"`
- **THEN** an audit_log row is written with command="skill create 4 grill", entity_type="skill", operation="create", entity_id=4, is_mutation=1, source="cli", username="admin"

#### Scenario: Audit subscriber logs RPC event
- **WHEN** the audit subscriber is registered
- **AND** an RPC-originated `CommandEvent` is published for `"skill rename 4 sauté"` by user `"rpc"`
- **THEN** an audit_log row is written with command="skill rename 4 sauté", source="rpc", username="rpc"

#### Scenario: Audit subscriber logs all topics
- **WHEN** events are published to topics `"skill.create.4"`, `"worker.grant-skill.3"`, and `"draft.commit.7"`
- **THEN** all three are written to the audit log

### Requirement: Repository gains repoLogCommandEvent
The `Repository` record SHALL include a new function `repoLogCommandEvent :: CommandEvent -> IO ()` that writes an audit_log row from the `CommandEvent` fields, mapping `ceSource` to the `source` column (`CLI` → `"cli"`, `RPC` → `"rpc"`).

#### Scenario: Source mapping
- **WHEN** `repoLogCommandEvent` is called with a `CommandEvent` where `ceSource = CLI`
- **THEN** the audit_log row has source="cli"

- **WHEN** `repoLogCommandEvent` is called with a `CommandEvent` where `ceSource = RPC`
- **THEN** the audit_log row has source="rpc"

### Requirement: Inline audit calls removed
The CLI's `repoLogCommand` call and the RPC handlers' `logRpc` calls SHALL be replaced by `publish` calls on `busCommands`. The audit subscriber is the sole writer to the audit log for command events.

#### Scenario: CLI no longer calls repoLogCommand inline
- **WHEN** a mutating CLI command is executed
- **THEN** `repoLogCommand` is NOT called directly; instead a `CommandEvent` is published

#### Scenario: RPC no longer calls logRpc inline
- **WHEN** a mutating RPC handler executes (for migrated handlers)
- **THEN** `logRpc` is NOT called directly; instead a `CommandEvent` is published

### Requirement: Audit subscriber registered before other subscribers
The audit subscriber SHALL be the first subscriber registered on `busCommands` so it is invoked first during publish iteration.

#### Scenario: Registration order
- **WHEN** the application starts up
- **THEN** the audit subscriber is registered before the terminal echo subscriber and any future subscribers
