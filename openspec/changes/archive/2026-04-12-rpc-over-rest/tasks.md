## 1. Expand REST API Endpoints

- [x] 1.1 Add skill create/delete endpoints (`POST /api/skills`, `DELETE /api/skills/:id`)
- [x] 1.2 Add station create/delete/hours/closure endpoints
- [x] 1.3 Add shift create/delete endpoints
- [x] 1.4 Add worker configuration endpoints (hours, overtime, prefs, variety, shift-prefs, weekend-only, seniority, cross-training, employment-status, overtime-model, pay-tracking, temp)
- [x] 1.5 Add worker skill grant/revoke endpoints (`POST`/`DELETE /api/workers/:id/skills/:skillId`)
- [x] 1.6 Add worker pairing endpoints (avoid-pairing, prefer-pairing)
- [x] 1.7 Add pin management endpoints (`GET`/`POST`/`DELETE /api/pins`)
- [x] 1.8 Add calendar mutation endpoints (commit, unfreeze, freeze-status)
- [x] 1.9 Add config write endpoints (set, presets, reset, pay-period)
- [x] 1.10 Add audit log endpoints (`GET /api/audit`, `POST /api/audit/replay`)
- [x] 1.11 Add checkpoint endpoints (list, create, commit, rollback)
- [x] 1.12 Add import/export endpoints
- [x] 1.13 Add absence type management endpoints (create, delete, set-allowance)
- [x] 1.14 Add user management endpoints (list, create, delete)
- [x] 1.15 Add hint session endpoints (close-station, pin, add-worker, waive-overtime, grant-skill, override-prefs, revert, apply, rebase, list)
- [x] 1.16 Add JSON request/response types in `Server.Json` for all new endpoints
- [x] 1.17 Add tests for all new REST endpoints in `ApiSpec.hs`

## 2. RPC Command Dispatch Layer

- [x] 2.1 Create `Server.Rpc` module with Servant API type for `/rpc/<group>/<operation>` endpoints
- [x] 2.2 Implement RPC handlers for admin entity CRUD (skill, station, shift, absence-type)
- [x] 2.3 Implement RPC handlers for worker configuration commands
- [x] 2.4 Implement RPC handlers for pin, calendar, config, audit, and checkpoint commands
- [x] 2.5 Implement RPC handlers for draft and schedule commands
- [x] 2.6 Implement RPC handlers for hint session (what-if) commands
- [x] 2.7 Implement RPC handlers for import/export, user, assignment, and context commands
- [x] 2.8 Implement RPC session management endpoints (create, resume)
- [x] 2.9 Add `X-Session-Id` header extraction and session context lookup
- [x] 2.10 Wire RPC audit logging with `source='rpc'` and typed metadata
- [x] 2.11 Mount RPC routes alongside REST routes in `Server.Api`
- [x] 2.12 Add tests for RPC endpoints

## 3. RPC Client Module

- [x] 3.1 Create `CLI.RpcClient` module with HTTP dispatch function mapping `Command` to RPC calls
- [x] 3.2 Implement JSON serialization/deserialization for all command arguments and responses
- [x] 3.3 Implement session management (create/resume session on startup, include `X-Session-Id` header)
- [x] 3.4 Implement error handling (HTTP error codes to user-facing messages, connection failures)
- [x] 3.5 Wire response JSON into existing CLI rendering functions for identical output

## 4. CLI Integration

- [x] 4.1 Add `--remote <url>` command-line flag to CLI argument parser
- [x] 4.2 Branch dispatch in CLI main: local mode (direct service calls) vs remote mode (RPC client)
- [x] 4.3 Ensure interactive flows (login, session resume prompt) run locally before entering RPC mode
- [x] 4.4 Add integration tests: CLI in remote mode against a test server

## 5. Verification

- [x] 5.1 Run full test suite — all existing tests still pass
- [x] 5.2 Run demo in local mode — verify no regressions
- [x] 5.3 Start server + CLI in remote mode — verify end-to-end command dispatch
- [x] 5.4 Verify audit log entries show correct `source` for CLI vs RPC-originated commands
