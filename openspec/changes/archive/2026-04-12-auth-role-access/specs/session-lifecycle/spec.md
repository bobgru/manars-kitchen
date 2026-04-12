## MODIFIED Requirements

### Requirement: Session creation on login
The system SHALL create a new session record when a user logs in and no active session exists (or the user chooses to start fresh). The session SHALL record the user ID, creation timestamp, last-active timestamp, and a randomly generated authentication token. The session SHALL be marked as active.

#### Scenario: First login creates a session with token
- **WHEN** a user logs in and has no active session
- **THEN** a new session is created with `is_active = 1`, `created_at` and `last_active_at` set to the current time, and a unique 64-character hex token
- **AND** the session ID and token are returned

#### Scenario: Start fresh closes old session
- **WHEN** a user logs in, has an active session, and chooses to start fresh
- **THEN** the old session is closed (`is_active = 0`) and a new session is created with a new token

### Requirement: Session repo functions
The repository SHALL provide functions for session lifecycle: `repoCreateSession` (user ID -> IO (SessionId, Token)), `repoGetActiveSession` (user ID -> IO (Maybe SessionId)), `repoTouchSession` (SessionId -> IO ()), `repoCloseSession` (SessionId -> IO ()), `repoGetSessionByToken` (Token -> IO (Maybe (SessionId, UserId, UTCTime))).

#### Scenario: Create and retrieve session
- **WHEN** `repoCreateSession` is called with a user ID
- **THEN** a session record is inserted and the new session ID and token are returned
- **AND** `repoGetActiveSession` for that user returns the new session ID

#### Scenario: Look up session by token
- **WHEN** `repoGetSessionByToken` is called with a valid token
- **THEN** it returns the session ID, user ID, and `last_active_at` timestamp

#### Scenario: Look up session by invalid token
- **WHEN** `repoGetSessionByToken` is called with an unknown token
- **THEN** it returns Nothing

#### Scenario: Close session makes it inactive
- **WHEN** `repoCloseSession` is called with a session ID
- **THEN** `repoGetActiveSession` for that user returns Nothing
- **AND** `repoGetSessionByToken` for that session's token returns Nothing

## ADDED Requirements

### Requirement: Session token storage
The sessions table SHALL include a `token TEXT NOT NULL` column storing the opaque authentication token. The column SHALL be indexed for efficient lookup.

#### Scenario: Token column exists
- **WHEN** the sessions table is queried
- **THEN** each session record includes a non-null `token` field

### Requirement: Session idle-timeout configuration
The system SHALL store the idle timeout duration in the `scheduler_config` table under the key `session_idle_timeout_minutes`. The default value SHALL be 30. The value SHALL be readable and updatable via the existing config endpoints.

#### Scenario: Default timeout
- **WHEN** no custom timeout has been configured
- **THEN** the idle timeout is 30 minutes

#### Scenario: Custom timeout via config
- **WHEN** an admin sets `session_idle_timeout_minutes` to 60 via `PUT /api/config/session_idle_timeout_minutes`
- **THEN** subsequent session expiry checks use 60 minutes as the threshold
