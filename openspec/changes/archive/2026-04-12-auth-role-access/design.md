## Context

The REST and RPC APIs share a single Warp server (`FullAPI = API :<|> RpcAPI`) and both call the service layer directly — RPC does **not** delegate to REST via HTTP. All ~80 endpoints currently accept a bare `Repository` and have no authentication or authorization. The foundation pieces exist: `User` type with `Admin`/`Normal` roles, bcrypt password hashing, `Service.Auth.login`, and a `sessions` table with lifecycle functions. What's missing is the HTTP-layer wiring: token management, request validation middleware, and per-endpoint role enforcement.

## Goals / Non-Goals

**Goals:**
- Every REST and RPC endpoint (except login) requires a valid, non-expired session token
- Admins can access all endpoints; Normal users (workers) are restricted to a safe subset
- Workers accessing worker-scoped endpoints can only read/modify their own data
- Sessions expire after a configurable idle timeout
- The auth mechanism works for browser SPAs (cookie or header) and CLI clients alike

**Non-Goals:**
- OAuth, OIDC, or external identity providers
- Fine-grained per-entity permissions beyond admin vs worker + self-scoping
- Rate limiting or brute-force protection (future change)
- CORS configuration (will be addressed with Admin UI change)
- Refresh tokens or token rotation

## Decisions

### 1. Opaque random session tokens (not JWT)

Sessions are already database-backed. On login, generate a random token (hex-encoded, 32 bytes via `System.Random` or `cryptonite`), store it in a new `token` column on the `sessions` table, and return it to the client. Subsequent requests present this token via `Authorization: Bearer <token>` header. The server looks up the token in the sessions table to resolve the user.

**Why not JWT:** JWTs require a signing secret, token expiry logic, and cannot be server-revoked without a blocklist — all complexity we don't need when we already have a sessions table and SQLite is in-process. Opaque tokens keep auth stateful and simple.

**Alternatives considered:**
- JWT with short expiry: adds a dependency (`jose` package), requires refresh flow, harder to revoke
- Cookie-based sessions: viable but `Authorization` header is simpler for both CLI and SPA clients; cookies can be added later as a convenience layer

### 2. Servant `AuthProtect` with generalized auth context

Use Servant's `AuthProtect` tagged type to thread an authenticated `User` value through the API type. Define a `type instance AuthServerData (AuthProtect "session") = User`. The auth handler (Servant's `AuthHandler`) extracts the `Authorization` header, looks up the token, checks expiry, resolves the user, and either returns `User` or throws a 401.

This changes every protected endpoint's type to include `AuthProtect "session" :>` and every handler to receive a `User` as its first argument. The login endpoint is defined outside the protected block so it remains public.

**Alternatives considered:**
- WAI middleware only (no Servant integration): simpler to wire but loses type safety — handlers wouldn't receive `User` in their signature, and the role/user would need to be pulled from a request vault at runtime
- Servant's `BasicAuth`: too limited (no session tokens, re-sends credentials every request)

### 3. API type restructuring: public vs protected

Split `FullAPI` into a small public section (login, optional health-check) and a protected section where `AuthProtect "session"` is applied once at the top level. This avoids repeating the auth combinator on every endpoint.

```haskell
type PublicAPI = "api" :> "login" :> ReqBody '[JSON] LoginReq :> Post '[JSON] LoginResp
           :<|> "api" :> "logout" :> AuthProtect "session" :> PostNoContent

type ProtectedAPI = AuthProtect "session" :> (API :<|> RpcAPI)

type FullAPI = PublicAPI :<|> ProtectedAPI
```

All existing REST and RPC endpoints are grouped under `ProtectedAPI` and receive `User` via the auth combinator.

### 4. Endpoint role classification

Define a simple role check as a helper function in the handler layer:

- **Admin-only**: All mutation endpoints for skills, stations, shifts, schedules, drafts, calendar, config, checkpoints, import/export, user management, absence approval/rejection, absence type management, pins
- **Worker-accessible**: Read-only endpoints for skills, stations, shifts, calendar, freeze-status, config. Worker-scoped mutations: `PUT /api/workers/:id/*` (only own ID), `POST /api/absences` (only own worker ID), `GET /api/absences/pending` (filtered to own). Hint endpoints scoped to own sessions.

The role check is a guard at the top of each handler:

```haskell
requireAdmin :: User -> Handler ()
requireAdmin u = when (userRole u /= Admin) $ throwApiError Forbidden
```

For worker self-scoping, compare `userWorkerId user` against the `:id` capture parameter.

**Alternatives considered:**
- Middleware-level route table with role tags: cleaner separation but harder to maintain as routes change, and loses access to parsed capture parameters needed for self-scoping
- Servant type-level role tagging (separate `AdminAPI`/`WorkerAPI`): heavy refactor, duplicates endpoints that both roles can access

### 5. Idle-timeout session expiration

The auth handler checks `last_active_at` against a configurable timeout (e.g., 30 minutes). If `now - last_active_at > timeout`, the session is treated as expired and the request gets a 401. The timeout value is stored in `scheduler_config` (existing key-value config table) so it can be adjusted at runtime.

On each authenticated request, `last_active_at` is touched — this means all requests (not just mutations) keep the session alive in the HTTP context, which differs from the CLI's "touch on mutation only" rule. The rationale: in a browser, any activity (including reads) signals the user is present.

Expired sessions are not deleted — they remain with `is_active = 1` but fail the timeout check. A periodic cleanup or explicit logout sets `is_active = 0`. This avoids race conditions with concurrent requests.

### 6. Token generation

Use `System.Random` (already a dependency) to generate 32 random bytes, hex-encoded to a 64-character string. This is sufficient for an internal restaurant scheduling tool. If stronger guarantees are needed later, swap to `cryptonite`'s secure random generator.

The token is stored in a new `token TEXT` column on the `sessions` table and indexed for fast lookup.

## Risks / Trade-offs

- **Breaking change for all API consumers**: Every endpoint now requires auth. The demo CLI must be updated to login first. → Mitigation: login is a single POST; the demo script can hardcode test credentials.
- **Handler signature churn**: Every handler gains a `User` parameter. → Mitigation: mechanical change, low risk; compiler enforces completeness.
- **Session token in SQLite**: Token lookup on every request adds a query. → Mitigation: SQLite is in-process with sub-millisecond reads; index on `token` column keeps it fast.
- **Idle timeout edge case**: A user making only reads in the CLI (where touch is mutation-only) could see their session expire while actively using the tool. → Mitigation: HTTP auth touches on all requests regardless; CLI behavior is unchanged (CLI sessions are separate from HTTP sessions).

## Open Questions

- Should the idle timeout default be 30 minutes or longer? (Can be changed via config after deployment.)
- Should there be a `GET /api/me` convenience endpoint returning the authenticated user's profile and role?
