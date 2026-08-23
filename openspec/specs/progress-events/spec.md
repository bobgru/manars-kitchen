### Requirement: ProgressEvent sum type
The system SHALL define a `ProgressEvent` sum type with at least an `OptimizeProgress OptProgress` constructor wrapping the existing `Domain.Optimizer.OptProgress` type. Additional constructors MAY be added by future changes.

#### Scenario: Optimizer progress wrapped in ProgressEvent
- **WHEN** the optimizer emits progress
- **THEN** the event is wrapped as `OptimizeProgress optProgress` and published to the bus

### Requirement: Optimizer publishes to bus instead of accepting callback
`Service.Optimize.optimizeSchedule` SHALL accept a `PubSub ProgressEvent` handle instead of a `(OptProgress -> IO ())` callback. It SHALL publish `OptimizeProgress` events to the bus at the same throttled intervals as before.

#### Scenario: Optimizer with subscriber
- **WHEN** a subscriber is registered on the bus
- **AND** `optimizeSchedule` runs with optimization enabled
- **THEN** the subscriber receives `OptimizeProgress` events at throttled intervals

#### Scenario: Optimizer with no subscriber
- **WHEN** no subscribers are registered on the bus
- **AND** `optimizeSchedule` runs with optimization enabled
- **THEN** the optimization completes normally and progress events are silently dropped

### Requirement: CLI subscribes to bus for optimizer output
The CLI SHALL create a `TopicBus ProgressEvent`, subscribe a handler that prints optimizer
progress to stdout (matching the current `[opt]` output format), invoke the generator with the
bus, and unsubscribe after the call returns. The generator so wired is `draft generate`.

#### Scenario: CLI output unchanged
- **WHEN** the user runs `draft generate` with optimization enabled
- **THEN** the `[opt] phase=... iter=... unfilled=... score=... elapsed=...` output appears in
  the same format as before

#### Scenario: Subscription does not outlive the call
- **WHEN** `draft generate` returns
- **THEN** the printer is unsubscribed, so a later unrelated publish on a shared bus prints
  nothing

### Requirement: Non-CLI callers may omit a subscriber
The REST and RPC draft-generate handlers SHALL pass a bus with no subscribers. Progress events
are dropped and the generate call completes normally.

#### Scenario: REST generate with no subscriber
- **WHEN** `POST /api/drafts/:id/generate` runs with optimization enabled
- **THEN** the response is the completed `ScheduleResult` and no progress is emitted anywhere
