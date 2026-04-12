## ADDED Requirements

### Requirement: Login endpoint
The system SHALL expose `POST /api/login` accepting a JSON body with `username` and `password` fields. On success it SHALL return `200` with a JSON body containing `token` (opaque session token) and `user` (authenticated user info including role and worker ID). On failure it SHALL return `401` with a JSON error body.

#### Scenario: Successful login
- **WHEN** a POST is made to `/api/login` with valid credentials
- **THEN** the response is `200` with `{"token": "<64-char hex>", "user": {"id": <int>, "username": "<string>", "role": "admin"|"normal", "workerId": <int>}}`
- **AND** a new active session is created in the sessions table with the returned token

#### Scenario: Invalid credentials
- **WHEN** a POST is made to `/api/login` with an unknown username or wrong password
- **THEN** the response is `401` with `{"error": "Invalid credentials"}`
- **AND** no session is created

### Requirement: Logout endpoint
The system SHALL expose `POST /api/logout` which requires a valid session token. It SHALL close the session (set `is_active = 0`) and return `204`.

#### Scenario: Successful logout
- **WHEN** a POST is made to `/api/logout` with a valid session token
- **THEN** the session is closed and the response is `204`
- **AND** subsequent requests with that token return `401`

#### Scenario: Logout with invalid token
- **WHEN** a POST is made to `/api/logout` with an invalid or expired token
- **THEN** the response is `401`

### Requirement: Session token generation
On successful login, the system SHALL generate a cryptographically random 32-byte token, hex-encode it to a 64-character string, and store it in the session record's `token` column.

#### Scenario: Token uniqueness
- **WHEN** two users log in concurrently
- **THEN** each receives a distinct token

#### Scenario: Token format
- **WHEN** a user logs in successfully
- **THEN** the returned token is a 64-character lowercase hexadecimal string

### Requirement: Token-based request authentication
All endpoints except `POST /api/login` SHALL require an `Authorization: Bearer <token>` header. The system SHALL look up the token in the sessions table. If the token is not found, the session is inactive, or the session has expired, the system SHALL respond with `401`.

#### Scenario: Valid token grants access
- **WHEN** a request includes `Authorization: Bearer <valid-token>`
- **AND** the session is active and not expired
- **THEN** the request proceeds with the authenticated user context

#### Scenario: Missing authorization header
- **WHEN** a request to a protected endpoint has no `Authorization` header
- **THEN** the response is `401` with `{"error": "Missing authorization"}`

#### Scenario: Invalid token
- **WHEN** a request includes `Authorization: Bearer <unknown-token>`
- **THEN** the response is `401` with `{"error": "Invalid session"}`

#### Scenario: Inactive session token
- **WHEN** a request includes a token for a session with `is_active = 0`
- **THEN** the response is `401` with `{"error": "Invalid session"}`

### Requirement: Idle-timeout session expiration
The system SHALL compare the session's `last_active_at` against the current time. If the elapsed time exceeds the configured idle timeout, the request SHALL be rejected with `401`. The idle timeout value SHALL be stored in the `scheduler_config` table under a well-known key and default to 30 minutes.

#### Scenario: Active session within timeout
- **WHEN** a request arrives with a valid token
- **AND** `last_active_at` is 10 minutes ago and the timeout is 30 minutes
- **THEN** the request proceeds normally

#### Scenario: Expired session beyond timeout
- **WHEN** a request arrives with a valid token
- **AND** `last_active_at` is 45 minutes ago and the timeout is 30 minutes
- **THEN** the response is `401` with `{"error": "Session expired"}`

#### Scenario: Configurable timeout
- **WHEN** the idle timeout config is changed from 30 to 60 minutes
- **AND** a session's `last_active_at` is 45 minutes ago
- **THEN** the request proceeds normally (within the new timeout)

### Requirement: Session touch on authenticated request
The system SHALL update `last_active_at` to the current time on every successfully authenticated HTTP request, regardless of whether the operation is a read or a mutation.

#### Scenario: GET request touches session
- **WHEN** an authenticated GET request is made to `/api/skills`
- **THEN** the session's `last_active_at` is updated to the current time

#### Scenario: POST request touches session
- **WHEN** an authenticated POST request is made to `/api/drafts`
- **THEN** the session's `last_active_at` is updated to the current time
