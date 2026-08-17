## Requirements

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

### Requirement: Stream mutation events
The SSE endpoint SHALL subscribe to the `busCommands` channel and forward every event whose metadata reports `cmIsMutation`, whatever its `ceSource`. Non-mutating events SHALL be dropped. Each event SHALL be formatted as an SSE `data:` line containing a JSON object with `command`, `source`, `username`, `entityType`, `operation`, `entityId`, `oldName`, `newName` and `clientId` fields.

Events are deliberately NOT filtered by `ceSource` or by `ceUsername`: a CLI or RPC mutation has to reach a connected browser, and a second tab of the same user has to see the first tab's changes. Suppressing a client's echo of its own command is the frontend's job, via `clientId`.

#### Scenario: GUI event is streamed
- **WHEN** a REST handler publishes a mutating `CommandEvent` with `ceSource == GUI`
- **AND** an SSE client is connected
- **THEN** the client receives an SSE event whose JSON carries the command string and `"source":"gui"`

#### Scenario: CLI event is streamed
- **WHEN** the CLI publishes a mutating `CommandEvent` with `ceSource == CLI`
- **AND** an SSE client is connected
- **THEN** the client receives the event

#### Scenario: Non-mutating event is not streamed
- **WHEN** a `CommandEvent` is published whose metadata reports `cmIsMutation == False`
- **AND** an SSE client is connected
- **THEN** the client does NOT receive an event

### Requirement: Structured rename fields
Rename events SHALL carry the entity's name before and after the rename as `oldName` and `newName`. A client SHALL NOT need to parse `command` to recover them: the reference in a rename command is an ID in some grammars (`skill rename 3 pastry`) and a name in others (`user rename alice alicia`), and the old name is gone from the database by the time the event fires. Where the command string cannot supply a name, the publisher SHALL attach it via `Audit.CommandMeta.withRenameNames`.

#### Scenario: Rename from any source carries both names
- **WHEN** a skill named `grill` is renamed to `broiler` via REST, RPC or the CLI
- **AND** an SSE client is connected
- **THEN** the event's JSON contains `"oldName":"grill"` and `"newName":"broiler"`

#### Scenario: Non-rename event leaves the fields null
- **WHEN** a mutating event that is not a rename is forwarded
- **THEN** `oldName` and `newName` are `null`

### Requirement: Role-based filtering
The SSE endpoint SHALL resolve the connected client's `User` and drop events the client's role would not be allowed to read over REST, mapping `cmEntityType` to a required role. A `Normal` user SHALL NOT receive events for entity types whose REST reads are `requireAdmin` or per-worker filtered: `user`, `worker`, `absence`, `import-export`, `checkpoint` and `what-if`. An event with no `cmEntityType` SHALL be dropped for a `Normal` user.

#### Scenario: Admin receives every mutation event
- **WHEN** any mutating event is published
- **AND** an SSE client is connected as an `Admin`
- **THEN** the client receives the event

#### Scenario: Admin-only event is dropped for a normal user
- **WHEN** a `worker set-hours` event is published
- **AND** an SSE client is connected as a `Normal` user
- **THEN** the client does NOT receive the event

#### Scenario: Openly readable event reaches a normal user
- **WHEN** a `skill create` event is published
- **AND** an SSE client is connected as a `Normal` user
- **THEN** the client receives the event

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
