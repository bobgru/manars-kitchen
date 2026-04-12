## ADDED Requirements

### Requirement: Session creation on login
The system SHALL create a new session record when a user logs in and no active session exists (or the user chooses to start fresh). The session SHALL record the user ID, creation timestamp, and last-active timestamp. The session SHALL be marked as active.

#### Scenario: First login creates a session
- **WHEN** a user logs in and has no active session
- **THEN** a new session is created with `is_active = 1`, `created_at` and `last_active_at` set to the current time, and the session ID is stored in `AppState`

#### Scenario: Start fresh closes old session
- **WHEN** a user logs in, has an active session, and chooses to start fresh
- **THEN** the old session is closed (`is_active = 0`) and a new session is created

### Requirement: Session resumption on login
The system SHALL check for an existing active session when a user logs in. If one exists, the system SHALL prompt the user to resume it or start a new session.

#### Scenario: Resume existing session
- **WHEN** a user logs in and has an active session and chooses to resume
- **THEN** the existing session ID is used and `last_active_at` is updated

#### Scenario: No active session skips prompt
- **WHEN** a user logs in and has no active session
- **THEN** a new session is created without prompting

### Requirement: Session touch on mutating commands
The system SHALL update the session's `last_active_at` timestamp each time a mutating command is executed. Non-mutating commands SHALL NOT update the timestamp.

#### Scenario: Mutating command updates timestamp
- **WHEN** a user runs `station add 1 grill`
- **THEN** the session's `last_active_at` is updated to the current time

#### Scenario: Non-mutating command does not update timestamp
- **WHEN** a user runs `station list`
- **THEN** the session's `last_active_at` is unchanged

### Requirement: Session close on quit
The system SHALL close the active session when the user types `quit` or `exit`. Closing a session SHALL set `is_active = 0`.

#### Scenario: Quit closes session
- **WHEN** a user types `quit`
- **THEN** the session record is updated to `is_active = 0` before the process exits

#### Scenario: Crash leaves session active
- **WHEN** the CLI process is killed without a clean quit
- **THEN** the session remains `is_active = 1` in the database and is offered for resumption on next login

### Requirement: Session repo functions
The repository SHALL provide functions for session lifecycle: `repoCreateSession` (user ID -> IO SessionId), `repoGetActiveSession` (user ID -> IO (Maybe SessionId)), `repoTouchSession` (SessionId -> IO ()), `repoCloseSession` (SessionId -> IO ()).

#### Scenario: Create and retrieve session
- **WHEN** `repoCreateSession` is called with a user ID
- **THEN** a session record is inserted and the new session ID is returned
- **AND** `repoGetActiveSession` for that user returns the new session ID

#### Scenario: Close session makes it inactive
- **WHEN** `repoCloseSession` is called with a session ID
- **THEN** `repoGetActiveSession` for that user returns Nothing
