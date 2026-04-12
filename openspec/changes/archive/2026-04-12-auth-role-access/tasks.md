## 1. Database and Token Infrastructure

- [x] 1.1 Add `token TEXT NOT NULL` column to the sessions table schema and create an index on it
- [x] 1.2 Add `repoGetSessionByToken :: Token -> IO (Maybe (SessionId, UserId, UTCTime))` to the repository
- [x] 1.3 Update `repoCreateSession` to generate a random 32-byte hex token, store it, and return `(SessionId, Token)`
- [x] 1.4 Add default `session_idle_timeout_minutes = 30` to the scheduler_config seed data

## 2. Auth Middleware

- [x] 2.1 Define `type instance AuthServerData (AuthProtect "session") = User` and the `AuthHandler` that extracts `Authorization: Bearer <token>`, looks up the session, checks expiry, resolves the user, and touches `last_active_at`
- [x] 2.2 Add login handler: `POST /api/login` accepting `{username, password}`, calling `Service.Auth.login`, creating a session, returning `{token, user}`
- [x] 2.3 Add logout handler: `POST /api/logout` requiring auth, closing the session, returning 204

## 3. API Type Restructuring

- [x] 3.1 Define `PublicAPI` (login endpoint) and `ProtectedAPI` (all existing endpoints wrapped with `AuthProtect "session"`)
- [x] 3.2 Update `FullAPI = PublicAPI :<|> ProtectedAPI` and update `fullApi` proxy
- [x] 3.3 Switch from `serve` to `serveWithContext` in server main, passing the auth handler in the Servant context

## 4. Handler Signature Updates

- [x] 4.1 Update all REST handlers in `Server.Handlers` to accept `User` as the first parameter
- [x] 4.2 Update all RPC handlers in `Server.Rpc` to accept `User` as the first parameter
- [x] 4.3 Wire updated handlers into the server functions (`server`, `rpcServer`, `fullServer`)

## 5. Endpoint Authorization

- [x] 5.1 Add `requireAdmin :: User -> Handler ()` and `requireSelf :: User -> WorkerId -> Handler ()` helper functions
- [x] 5.2 Add `requireAdmin` guard to all admin-only handlers (skill/station/shift CRUD, draft management, calendar mutations, config writes, checkpoints, import/export, user management, absence type management, absence approval/rejection, pin management, audit log)
- [x] 5.3 Add self-scoping guards to worker configuration endpoints (`PUT /api/workers/:id/*`): allow if admin or if worker ID matches `userWorkerId`
- [x] 5.4 Add self-scoping to absence requests: `POST /api/absences` checks body's `workerId` matches `userWorkerId`; `GET /api/absences/pending` filters to own absences for normal users
- [x] 5.5 Add self-scoping to hint endpoints: validate `sessionId` belongs to the authenticated user

## 6. Error Responses

- [x] 6.1 Ensure 401 and 403 responses return JSON `{"error": "<message>"}` with `Content-Type: application/json` (not Servant's default plain text)

## 7. Testing

- [x] 7.1 Add integration tests for login (success, invalid credentials) and logout
- [x] 7.2 Add integration tests for unauthenticated access (401 on protected endpoints)
- [x] 7.3 Add integration tests for session expiry (request after idle timeout returns 401)
- [x] 7.4 Add integration tests for role enforcement (admin-only endpoints return 403 for normal users)
- [x] 7.5 Add integration tests for worker self-scoping (worker can access own data, blocked from others)
- [x] 7.6 Verify the demo still works end-to-end with login step added
