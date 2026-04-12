## ADDED Requirements

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
The CLI SHALL create a `PubSub ProgressEvent` bus, subscribe a handler that prints optimizer progress to stdout (matching the current `[opt]` output format), call `optimizeSchedule` with the bus, and unsubscribe after the call returns.

#### Scenario: CLI output unchanged
- **WHEN** the user runs schedule optimization via the CLI
- **THEN** the `[opt] phase=... iter=... unfilled=... score=... elapsed=...` output appears exactly as before
