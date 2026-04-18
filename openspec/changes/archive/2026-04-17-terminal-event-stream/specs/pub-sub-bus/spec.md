## MODIFIED Requirements

### Requirement: Create a new bus
The system SHALL provide a function to create a new `TopicBus e` bus with no initial subscribers.

#### Scenario: Fresh bus has no subscribers
- **WHEN** a new `TopicBus` bus is created
- **THEN** the bus has zero subscribers and is ready for use

## ADDED Requirements

### Requirement: GUI source type
The `Source` type SHALL include a `GUI` constructor alongside `CLI`, `RPC`, and `Demo`. The `sourceString` function SHALL map `GUI` to `"gui"`.

#### Scenario: GUI source string
- **WHEN** `sourceString GUI` is called
- **THEN** the result is `"gui"`

#### Scenario: REST handlers publish as GUI
- **WHEN** a REST handler publishes a `CommandEvent` to the bus
- **THEN** the event's `ceSource` field is `GUI`
