## Why

The REST and RPC APIs expose ~80 endpoints covering every administrative and scheduling operation, but none require authentication or enforce authorization. Before building the Admin UI and Worker UI, every endpoint must verify the caller's identity and role. The foundation pieces — users table with bcrypt passwords, Admin/Normal roles, and database-backed sessions — already exist; what's missing is the HTTP-level wiring that connects them to request handling.

## What Changes

- Add a login endpoint that authenticates credentials and returns a session token (opaque, mapping to the existing sessions table)
- Add a logout endpoint that closes the session
- Add idle-timeout session expiration: sessions expire after a configurable period of inactivity (based on `last_active_at`); expired sessions are rejected with 401
- Add WAI middleware that extracts the session token from requests, validates it against the sessions table (checking expiry), and injects the authenticated user into the request context
- Integrate Servant's `AuthProtect` combinator so every protected endpoint receives a verified `User` value
- Classify each endpoint as admin-only or worker-accessible and enforce role checks in handlers
- Workers can only access their own data (schedule, absences, availability, preferences) and read-only shared data (skills, stations, shifts)
- Exempt the login endpoint (and optionally a health-check) from auth requirements
- **BREAKING**: All existing REST and RPC endpoints (except login) will reject unauthenticated requests with 401

## Capabilities

### New Capabilities
- `auth-middleware`: WAI/Servant middleware for token extraction, session validation (including idle-timeout expiry), and user context injection
- `endpoint-authorization`: Per-endpoint role classification and enforcement (admin-only vs worker-accessible), including worker self-scoping rules

### Modified Capabilities
- `rest-api-endpoints`: Every endpoint gains an authenticated user context; handler signatures change to accept `User`
- `rest-api-server`: Server startup wires in auth middleware; application context carries session validation logic
- `session-lifecycle`: Sessions gain idle-timeout expiry; touch-on-access keeps sessions alive; expired sessions are rejected

## Impact

- **Server code**: All handler functions in both `Server.Handlers` and `Server.Rpc` gain a `User` parameter; new middleware module; API type changes throughout
- **CLI**: The CLI's RPC client must login first and attach the session token to subsequent requests
- **Dependencies**: No new external packages required (session tokens are opaque IDs validated against SQLite; bcrypt is already present)
- **Database**: Possible addition of a timeout configuration column or table; expiry logic applied to existing `last_active_at` column
- **Testing**: Integration tests need a test-user setup step; unauthenticated requests must be tested for 401; expired-session scenarios must be covered
