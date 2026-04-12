## ADDED Requirements

### Requirement: CLI remote mode flag
The CLI SHALL accept a `--remote <url>` flag that causes all commands to be dispatched via HTTP to the specified server URL instead of calling service functions directly. When `--remote` is not provided, the CLI SHALL operate in local mode (current behavior).

#### Scenario: Remote mode flag
- **WHEN** the CLI is started with `--remote http://localhost:8080`
- **THEN** all commands are dispatched as RPC HTTP calls to `http://localhost:8080/rpc/...`

#### Scenario: Local mode default
- **WHEN** the CLI is started without `--remote`
- **THEN** commands are dispatched via direct service-layer function calls (existing behavior)

### Requirement: RPC client command dispatch
The RPC client module SHALL provide a dispatch function that accepts a `Command` value and translates it to the corresponding RPC HTTP call. The function SHALL serialize command arguments to JSON, make the POST request, and deserialize the response.

#### Scenario: Dispatch a skill create command
- **WHEN** the RPC client dispatches a `SkillCreate 4 "pastry" "Pastry skills"` command to a running server
- **THEN** it makes a POST to `/rpc/skill/create` with the appropriate JSON body
- **AND** returns the server's response

#### Scenario: Dispatch a schedule list command
- **WHEN** the RPC client dispatches a `ScheduleList` command
- **THEN** it makes a POST to `/rpc/schedule/list` with body `{}`
- **AND** returns the list of schedule names from the response

### Requirement: RPC client session management
The RPC client SHALL obtain a session ID at startup (by calling `/rpc/session/create` or `/rpc/session/resume`) and include it as an `X-Session-Id` header on all subsequent RPC requests.

#### Scenario: Session established on startup
- **WHEN** the CLI starts in remote mode
- **AND** the user logs in
- **THEN** the RPC client calls `/rpc/session/create` and stores the returned session ID

#### Scenario: Session ID included on requests
- **WHEN** the RPC client has an active session ID
- **AND** any command is dispatched
- **THEN** the HTTP request includes the `X-Session-Id` header

### Requirement: RPC client error handling
The RPC client SHALL interpret HTTP error responses (400, 404, 409, 500) and present the error message from the JSON body to the user in the same format as local-mode errors.

#### Scenario: Server returns 404
- **WHEN** the RPC client dispatches a command and the server returns `404` with `{"error": "Worker not found: 999"}`
- **THEN** the CLI displays "Worker not found: 999" (same as local-mode error output)

#### Scenario: Server unreachable
- **WHEN** the RPC client cannot connect to the server
- **THEN** the CLI displays a connection error message and does not crash

### Requirement: RPC client output rendering
The RPC client SHALL pass JSON responses to the existing CLI rendering functions so that output formatting (tabular, compact, by-worker, by-station) is identical in local and remote modes.

#### Scenario: Schedule view output matches
- **WHEN** a schedule view command is dispatched in remote mode
- **THEN** the output format is identical to the same command run in local mode
