## MODIFIED Requirements

### Requirement: JSON error responses
All error responses (400, 401, 403, 404, 409, 500) SHALL return a JSON body of the form `{"error": "<message>"}` with `Content-Type: application/json`.

#### Scenario: Unauthenticated request returns JSON 401
- **WHEN** a request is made without an `Authorization` header
- **THEN** the response is `401` with `Content-Type: application/json` and body `{"error": "Missing authorization"}`

#### Scenario: Forbidden request returns JSON 403
- **WHEN** a normal user accesses an admin-only endpoint
- **THEN** the response is `403` with `Content-Type: application/json` and body `{"error": "Forbidden"}`

## ADDED Requirements

### Requirement: All protected endpoints receive authenticated user
Every REST endpoint (except `POST /api/login`) SHALL receive the authenticated `User` value resolved by the auth middleware. Handler functions SHALL accept `User` as their first parameter.

#### Scenario: Handler has access to user identity
- **WHEN** an authenticated request is made to any protected endpoint
- **THEN** the handler receives the full `User` record including `userId`, `userRole`, and `userWorkerId`
