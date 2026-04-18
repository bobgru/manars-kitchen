# topic-bus Specification

## Purpose
Topic-routed typed pub/sub bus with regex-matched subscriptions. Replaces the flat `PubSub e` bus with `TopicBus e`, adding topic-based routing while preserving type safety, fire-and-forget semantics, and MVar-protected thread safety.

## Requirements

### Requirement: Topic type
The system SHALL define a `Topic` newtype wrapping `String`, with `Eq`, `Ord`, and `Show` instances.

#### Scenario: Topic construction
- **WHEN** `Topic "skill.create.4"` is constructed
- **THEN** it can be compared, ordered, and shown as `"skill.create.4"`

### Requirement: Create a new topic bus
The system SHALL provide `newTopicBus :: IO (TopicBus e)` to create a bus with no subscribers.

#### Scenario: Fresh bus has no subscribers
- **WHEN** a new `TopicBus` is created
- **THEN** the bus has zero subscribers and is ready for use

### Requirement: Subscribe with regex pattern
The system SHALL provide `subscribe :: TopicBus e -> String -> (Topic -> e -> IO ()) -> IO SubscriptionId` that registers a callback with a regex pattern. The pattern SHALL be compiled to a `Regex` at subscription time.

#### Scenario: Exact-match subscription
- **WHEN** a callback is subscribed with pattern `"skill\\.create\\.4"`
- **AND** an event is published to topic `"skill.create.4"`
- **THEN** the callback is invoked with the topic and event

#### Scenario: Wildcard subscription receives all events
- **WHEN** a callback is subscribed with pattern `".*"`
- **AND** events are published to topics `"skill.create.4"` and `"worker.grant-skill.3"`
- **THEN** the callback is invoked for both events

#### Scenario: Prefix subscription
- **WHEN** a callback is subscribed with pattern `"skill\\..*"`
- **AND** events are published to `"skill.create.4"` and `"worker.grant-skill.3"`
- **THEN** the callback is invoked only for `"skill.create.4"`

#### Scenario: Command-level subscription
- **WHEN** a callback is subscribed with pattern `".*\\.create\\..*"`
- **AND** events are published to `"skill.create.4"` and `"skill.rename.4"`
- **THEN** the callback is invoked only for `"skill.create.4"`

#### Scenario: Pattern is anchored
- **WHEN** a callback is subscribed with pattern `"skill"`
- **AND** an event is published to `"skill.create.4"`
- **THEN** the callback is NOT invoked (pattern must match the full topic)

### Requirement: Publish with topic routing
The system SHALL provide `publish :: TopicBus e -> Topic -> e -> IO ()` that delivers the event only to subscribers whose compiled regex matches the topic string.

#### Scenario: Multiple subscribers with different patterns
- **WHEN** subscriber A registers with pattern `"skill\\..*"` and subscriber B registers with pattern `"worker\\..*"`
- **AND** an event is published to topic `"skill.create.4"`
- **THEN** only subscriber A's callback is invoked

#### Scenario: Multiple matching subscribers all receive event
- **WHEN** subscriber A registers with `".*"` and subscriber B registers with `"skill\\..*"`
- **AND** an event is published to `"skill.create.4"`
- **THEN** both callbacks are invoked

### Requirement: Callback receives topic
The subscriber callback SHALL receive both the `Topic` and the event value, so the subscriber can inspect which specific topic triggered the match.

#### Scenario: Callback inspects topic
- **WHEN** a callback subscribed with `"skill\\..*"` receives an event
- **THEN** the callback's `Topic` argument is the specific topic that was published (e.g., `Topic "skill.create.4"`)

### Requirement: Unsubscribe from a topic bus
The system SHALL provide `unsubscribe :: TopicBus e -> SubscriptionId -> IO ()`. After unsubscription, the callback SHALL NOT be invoked for subsequent events.

#### Scenario: Unsubscribed callback stops receiving
- **WHEN** a callback is subscribed and then unsubscribed
- **AND** a matching event is published
- **THEN** the callback is NOT invoked

#### Scenario: Unsubscribing one does not affect others
- **WHEN** two callbacks are subscribed and one is unsubscribed
- **AND** a matching event is published
- **THEN** only the remaining subscriber's callback is invoked

### Requirement: Publish with no matching subscribers drops events
The system SHALL silently drop published events when no subscriber's pattern matches the topic.

#### Scenario: No pattern matches
- **WHEN** subscriber A is registered with pattern `"worker\\..*"`
- **AND** an event is published to topic `"skill.create.4"`
- **THEN** no callbacks are invoked and no error occurs

#### Scenario: Empty bus
- **WHEN** an event is published to a bus with no subscribers
- **THEN** no error occurs and the event is silently discarded

### Requirement: Thread-safe bus operations
All bus operations (subscribe, unsubscribe, publish) SHALL be safe to call from concurrent threads. The subscriber map SHALL be protected by `MVar`.

#### Scenario: Concurrent subscribe and publish
- **WHEN** one thread subscribes while another publishes
- **THEN** both operations complete without error or corruption

### Requirement: AppBus container
The system SHALL define an `AppBus` record holding typed channels:

```
AppBus
  busCommands :: TopicBus CommandEvent
  busProgress :: TopicBus ProgressEvent
```

The system SHALL provide `newAppBus :: IO AppBus` that creates all channels.

#### Scenario: Independent channels
- **WHEN** an event is published on `busCommands`
- **THEN** subscribers on `busProgress` are not affected, and vice versa

### Requirement: buildTopic function
The system SHALL provide `buildTopic :: CommandMeta -> Topic` that constructs a dot-separated topic string from `cmEntityType`, `cmOperation`, and `cmEntityId`.

#### Scenario: Full metadata
- **WHEN** `buildTopic` is called with CommandMeta where entityType="skill", operation="create", entityId=4
- **THEN** it returns `Topic "skill.create.4"`

#### Scenario: Two-entity command uses primary ID
- **WHEN** `buildTopic` is called with CommandMeta where entityType="worker", operation="grant-skill", entityId=3, targetId=5
- **THEN** it returns `Topic "worker.grant-skill.3"`

#### Scenario: Missing entity ID
- **WHEN** `buildTopic` is called with CommandMeta where entityType="draft", operation="list", entityId=Nothing
- **THEN** it returns `Topic "draft.list"`

#### Scenario: Unrecognized command
- **WHEN** `buildTopic` is called with CommandMeta where all fields are Nothing
- **THEN** it returns `Topic ""`
