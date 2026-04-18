### Requirement: Create a new bus
The system SHALL provide a function to create a new `TopicBus e` bus with no initial subscribers.

#### Scenario: Fresh bus has no subscribers
- **WHEN** a new `TopicBus` bus is created
- **THEN** the bus has zero subscribers and is ready for use

### Requirement: Subscribe to a bus
The system SHALL provide a function to register a callback `(e -> IO ())` on a bus, returning a unique `SubscriptionId` that can be used to unsubscribe.

#### Scenario: Single subscriber receives events
- **WHEN** a callback is subscribed to a bus
- **AND** an event is published to that bus
- **THEN** the callback is invoked with the published event

#### Scenario: Multiple subscribers each receive events
- **WHEN** two callbacks are subscribed to the same bus
- **AND** an event is published
- **THEN** both callbacks are invoked with the published event

### Requirement: Unsubscribe from a bus
The system SHALL provide a function to remove a subscription by its `SubscriptionId`. After unsubscription, the callback SHALL NOT be invoked for subsequent events.

#### Scenario: Unsubscribed callback stops receiving
- **WHEN** a callback is subscribed and then unsubscribed
- **AND** an event is published
- **THEN** the callback is NOT invoked

#### Scenario: Unsubscribing one does not affect others
- **WHEN** two callbacks are subscribed and one is unsubscribed
- **AND** an event is published
- **THEN** only the remaining subscriber's callback is invoked

### Requirement: Publish with no subscribers drops events
The system SHALL silently drop published events when no subscribers are registered (fire-and-forget semantics).

#### Scenario: Publish to empty bus
- **WHEN** an event is published to a bus with no subscribers
- **THEN** no error occurs and the event is silently discarded

### Requirement: Thread-safe bus operations
All bus operations (subscribe, unsubscribe, publish) SHALL be safe to call from concurrent threads. The subscriber map SHALL be protected by `MVar`.

#### Scenario: Concurrent subscribe and publish
- **WHEN** one thread subscribes while another publishes
- **THEN** both operations complete without error or corruption

### Requirement: GUI source type
The `Source` type SHALL include a `GUI` constructor alongside `CLI`, `RPC`, and `Demo`. The `sourceString` function SHALL map `GUI` to `"gui"`.

#### Scenario: GUI source string
- **WHEN** `sourceString GUI` is called
- **THEN** the result is `"gui"`

#### Scenario: REST handlers publish as GUI
- **WHEN** a REST handler publishes a `CommandEvent` to the bus
- **THEN** the event's `ceSource` field is `GUI`
