## MODIFIED Requirements

### Requirement: Standalone HTTP server executable
The system SHALL provide a `manars-server` executable that starts a Warp HTTP server serving the REST API, RPC API, and frontend static files. The server SHALL wire in the Servant `AuthHandler` that validates session tokens on all protected endpoints.

#### Scenario: Default startup
- **WHEN** `manars-server` is started with no arguments
- **THEN** it opens the SQLite database at `run-db/manars-kitchen.db`
- **AND** serves static files from `web/dist/`
- **AND** listens on port 8080
- **AND** all endpoints except `POST /api/login` require `Authorization: Bearer <token>`

#### Scenario: Custom database path
- **WHEN** `manars-server` is started with one argument
- **THEN** it uses that argument as the database path
- **AND** serves static files from `web/dist/`
- **AND** listens on port 8080

#### Scenario: Custom database path and port
- **WHEN** `manars-server` is started with two arguments
- **THEN** it uses the first as the database path and the second as the port number
- **AND** serves static files from `web/dist/`
