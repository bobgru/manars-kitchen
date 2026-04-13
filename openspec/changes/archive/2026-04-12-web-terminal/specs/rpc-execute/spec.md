## ADDED Requirements

### Requirement: Raw command execution endpoint
The system SHALL provide a `POST /rpc/execute` endpoint that accepts a JSON body `{"command": "<command string>"}` and returns the command's formatted text output with content type `text/plain`.

#### Scenario: Successful command execution
- **WHEN** an authenticated user POSTs `{"command": "skill list"}` to `/rpc/execute`
- **THEN** the server parses the command using the existing CLI parser
- **AND** executes it against the service layer
- **AND** returns HTTP 200 with `Content-Type: text/plain` and the same formatted text the CLI would display

#### Scenario: Unknown command
- **WHEN** an authenticated user POSTs `{"command": "notacommand"}` to `/rpc/execute`
- **THEN** the server returns HTTP 200 with a text body containing the "Unknown command" message (matching CLI behavior)

#### Scenario: Command execution error
- **WHEN** an authenticated user POSTs a valid command that fails (e.g., deleting a nonexistent entity)
- **THEN** the server returns HTTP 200 with the error message as text (matching CLI behavior, not an HTTP error code)

#### Scenario: Help command
- **WHEN** an authenticated user POSTs `{"command": "help"}` to `/rpc/execute`
- **THEN** the server returns the top-level help text listing all command groups

#### Scenario: Help for a specific group
- **WHEN** an authenticated user POSTs `{"command": "help draft"}` to `/rpc/execute`
- **THEN** the server returns help text for the draft command group

### Requirement: Authentication required
The `/rpc/execute` endpoint SHALL require a valid `Authorization: Bearer <token>` header. Unauthenticated requests SHALL receive a 401 response.

#### Scenario: Missing auth token
- **WHEN** a POST is made to `/rpc/execute` without an `Authorization` header
- **THEN** the response is HTTP 401

### Requirement: Audit logging for executed commands
Commands executed via `/rpc/execute` SHALL be logged to the audit log with `source='web'`, using the same structured classification as CLI and RPC commands.

#### Scenario: Command appears in audit log
- **WHEN** a user executes `skill create 5 Grill` via `/rpc/execute`
- **THEN** the audit log contains an entry with the command string, structured metadata, and `source='web'`
