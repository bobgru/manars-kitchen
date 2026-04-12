## ADDED Requirements

### Requirement: Standalone HTTP server executable
The system SHALL provide a `manars-server` executable that starts a Warp HTTP server serving the REST API.

#### Scenario: Default startup
- **WHEN** `manars-server` is started with no arguments
- **THEN** it opens the SQLite database at `run-db/manars-kitchen.db`
- **AND** listens on port 8080

#### Scenario: Custom database path
- **WHEN** `manars-server` is started with one argument
- **THEN** it uses that argument as the database path
- **AND** listens on port 8080

#### Scenario: Custom database path and port
- **WHEN** `manars-server` is started with two arguments
- **THEN** it uses the first as the database path and the second as the port number

### Requirement: Server uses existing SQLite repository
The server SHALL create a SQLite repository via `mkSQLiteRepo` and pass it to the servant application. No new persistence layer is introduced.
