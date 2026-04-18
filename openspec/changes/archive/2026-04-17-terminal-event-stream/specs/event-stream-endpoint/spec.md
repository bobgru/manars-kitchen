## ADDED Requirements

### Requirement: SSE endpoint exists
The server SHALL expose a `GET /api/events` endpoint that returns a `text/event-stream` response. The connection SHALL remain open, streaming events as they occur.

#### Scenario: Successful connection
- **WHEN** an authenticated client sends `GET /api/events?token=<valid-token>`
- **THEN** the server responds with status 200
- **AND** `Content-Type: text/event-stream`
- **AND** the connection remains open

#### Scenario: Unauthenticated request
- **WHEN** a client sends `GET /api/events` without a token or with an invalid token
- **THEN** the server responds with status 401

### Requirement: SSE authentication via query parameter
The endpoint SHALL accept the session token as a `token` query parameter. The token SHALL be validated using the same session validation logic as the auth middleware (session lookup, idle timeout, user resolution).

#### Scenario: Expired session token
- **WHEN** a client connects with an expired or invalid session token
- **THEN** the server responds with status 401

### Requirement: Stream GUI command events
The SSE endpoint SHALL subscribe to the `busCommands` channel and forward events where `ceSource == GUI` to the connected client. Each event SHALL be formatted as an SSE `data:` line containing a JSON object with `command`, `source`, and `username` fields.

#### Scenario: GUI event is streamed
- **WHEN** a REST handler publishes a `CommandEvent` with `ceSource == GUI`
- **AND** an SSE client is connected
- **THEN** the client receives an SSE event with `data: {"command":"...","source":"gui","username":"..."}`

#### Scenario: RPC event is not streamed
- **WHEN** an RPC handler publishes a `CommandEvent` with `ceSource == RPC`
- **AND** an SSE client is connected
- **THEN** the client does NOT receive an event

### Requirement: Same-user filtering
The SSE endpoint SHALL only forward GUI events whose `ceUsername` matches the username of the connected client. Events from other users SHALL be silently dropped. Since the application enforces one active session per user, this achieves same-session isolation.

#### Scenario: Event from same user is forwarded
- **WHEN** a GUI event is published with `ceUsername == "admin"`
- **AND** an SSE client is connected as user `"admin"`
- **THEN** the client receives the event

#### Scenario: Event from different user is dropped
- **WHEN** a GUI event is published with `ceUsername == "other"`
- **AND** an SSE client is connected as user `"admin"`
- **THEN** the client does NOT receive the event

### Requirement: Keepalive comments
The SSE endpoint SHALL send a `:keepalive` comment every 30 seconds to prevent proxy and browser timeouts.

#### Scenario: Idle connection receives keepalive
- **WHEN** 30 seconds pass with no events to forward
- **THEN** the server sends `:keepalive\n\n` to the client

### Requirement: Clean disconnection
When the SSE client disconnects, the server SHALL unsubscribe from the bus and release all resources. The server SHALL use a bracket pattern to guarantee cleanup.

#### Scenario: Client disconnects
- **WHEN** the SSE client closes the connection
- **THEN** the server unsubscribes from `busCommands`
- **AND** no further callbacks are invoked for that subscription

### Requirement: WAI-level implementation
The SSE endpoint SHALL be implemented as a WAI `Application` using `responseStream`, handled in the `spaFallback` middleware before Servant routing. It SHALL NOT use Servant streaming combinators.

#### Scenario: Route interception
- **WHEN** a request arrives for `GET /api/events`
- **THEN** the `spaFallback` middleware intercepts it and delegates to `eventStreamApp`
- **AND** the request does NOT reach the Servant application
