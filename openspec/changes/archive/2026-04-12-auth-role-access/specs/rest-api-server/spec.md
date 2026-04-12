## MODIFIED Requirements

### Requirement: Standalone HTTP server executable
The system SHALL provide a `manars-server` executable that starts a Warp HTTP server serving the REST API. The server SHALL wire in the Servant `AuthHandler` that validates session tokens on all protected endpoints.

#### Scenario: Default startup
- **WHEN** `manars-server` is started with no arguments
- **THEN** it opens the SQLite database at `run-db/manars-kitchen.db`
- **AND** listens on port 8080
- **AND** all endpoints except `POST /api/login` require `Authorization: Bearer <token>`

#### Scenario: Custom database path
- **WHEN** `manars-server` is started with one argument
- **THEN** it uses that argument as the database path
- **AND** listens on port 8080

#### Scenario: Custom database path and port
- **WHEN** `manars-server` is started with two arguments
- **THEN** it uses the first as the database path and the second as the port number

## ADDED Requirements

### Requirement: Auth handler wired into Servant context
The server SHALL create a Servant `Context` containing the `AuthHandler` for `AuthProtect "session"`. The auth handler SHALL extract the `Authorization: Bearer <token>` header, look up the token in the sessions table, verify the session is active and not expired, and return the resolved `User` or throw a `401` error.

#### Scenario: Server context includes auth handler
- **WHEN** the server starts
- **THEN** the Servant application is created with `serveWithContext` including the auth handler
- **AND** protected endpoints receive the resolved `User`

### Requirement: Public and protected API split
The server SHALL define a `FullAPI` composed of a public section (login) and a protected section (all other endpoints). The protected section SHALL apply `AuthProtect "session"` so that all nested endpoints inherit authentication.

#### Scenario: Login is accessible without token
- **WHEN** a POST is made to `/api/login` without an `Authorization` header
- **THEN** the request is routed to the login handler (not rejected by auth middleware)

#### Scenario: Other endpoints require token
- **WHEN** a GET is made to `/api/skills` without an `Authorization` header
- **THEN** the response is `401`
