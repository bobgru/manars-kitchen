## Context

The CLI currently calls service functions directly via in-process Haskell function calls. The REST API exposes ~20 endpoints for drafts, calendar, absences, skills/stations/shifts (read-only), schedules, and config. The CLI has ~140 commands spanning admin entity management, pins, import/export, audit, checkpoints, calendar mutations, hint sessions, and more. The web interface roadmap (step 5) requires the CLI to operate as a thin HTTP client so that the server becomes the single source of truth.

The `Command` ADT in `CLI.Commands` enumerates all CLI commands. The `CommandClassifier` module already provides `classify`/`render` for structured metadata. The audit log has a `source` column that distinguishes origin (`'cli'`, and can accept `'rpc'`).

## Goals / Non-Goals

**Goals:**
- Every CLI command callable via a single HTTP POST to `/rpc/<command-group>/<operation>`
- RPC handlers implemented by calling existing service-layer functions (same as REST handlers), not by composing multiple REST calls — this avoids unnecessary HTTP round-trips within the same server process
- New REST endpoints added for all operations not yet exposed, so the full API surface is available to both RPC and REST consumers
- CLI gains a `--remote <url>` mode that dispatches commands via RPC instead of direct service calls
- RPC-originated commands logged in audit log with `source='rpc'`
- Session context (entity contexts, unfrozen ranges) managed server-side via session ID

**Non-Goals:**
- Authentication/authorization — deferred to the Auth change (roadmap step 7)
- WebSocket or streaming for long-running operations — pub/sub SSE is a separate concern
- Breaking changes to existing REST endpoints
- Changing the CLI command syntax or the `Command` ADT
- RPC for interactive flows (login prompts, session resume prompts) — the CLI handles these locally before entering RPC mode

## Decisions

### 1. RPC endpoints call service functions directly, not REST

The roadmap describes RPC as "a sequence of REST calls," but composing HTTP calls within the same server process adds latency, error-handling complexity, and serialization overhead for no benefit. Instead, RPC handlers and REST handlers both call the same service-layer functions. The REST API remains the real contract for external consumers; the RPC layer is a command-oriented convenience for the CLI.

**Alternative considered:** RPC-as-REST-composition. Rejected because it doubles HTTP overhead, complicates error propagation, and makes the server depend on its own REST API internally.

### 2. URL scheme: `/rpc/<group>/<operation>`

RPC endpoints use a two-level path: entity group + operation. Examples:
- `POST /rpc/skill/create` — body: `{"id": 4, "name": "pastry", "description": "..."}`
- `POST /rpc/worker/set-hours` — body: `{"workerId": 2, "hours": 40}`
- `POST /rpc/draft/generate` — body: `{"draftId": 1, "workerIds": [1,2,3]}`
- `POST /rpc/calendar/view` — body: `{"from": "2026-04-01", "to": "2026-04-30"}`

All RPC endpoints are POST (even reads) because the purpose is command dispatch, not resource modeling. Each endpoint accepts a JSON body matching the command's arguments and returns a JSON result.

**Alternative considered:** Single `POST /rpc` with a `command` field in the body. Rejected because per-command endpoints give better routing, logging, and documentation.

### 3. Session ID passed as header

RPC requests include an `X-Session-Id` header. The server uses this to look up session context (entity contexts, unfrozen ranges). The CLI obtains a session ID at startup (via a `/rpc/session/create` or `/rpc/session/resume` call) and includes it on subsequent requests.

**Alternative considered:** Session ID in request body. Rejected because it's cross-cutting (every command would need it), and headers are the conventional place for request metadata.

### 4. Shared request/response types in a `Common` module

JSON request/response types for RPC endpoints are defined alongside the REST types in `Server.Json` (or a new `Server.RpcJson` if the file grows too large). The CLI's RPC client imports these types from a shared library, ensuring type safety across the wire.

### 5. CLI dispatch architecture

The CLI gains a `RpcClient` module that mirrors the `handleCommand` dispatch but sends HTTP requests instead of calling service functions. A `--remote <url>` flag selects between local mode (direct service calls, current behavior) and remote mode (RPC client). The `Command` ADT is unchanged — only the dispatch layer differs.

### 6. Phased REST endpoint expansion

Rather than adding all ~120 missing REST endpoints at once, this change adds them grouped by domain area:
- Admin entity CRUD (skills, stations, shifts, workers, absence types)
- Worker configuration (hours, prefs, seniority, employment status, overtime, etc.)
- Pins (add, remove, list)
- Calendar mutations (commit, unfreeze, freeze-status)
- Config writes (set, presets, reset, pay-period config)
- Audit log (list, replay)
- Checkpoints (create, commit, rollback, list)
- Import/export
- Hint sessions (all what-if operations)

Each group becomes a set of REST endpoints AND corresponding RPC endpoints.

### 7. Audit logging with source='rpc'

RPC handlers call a variant of `repoLogCommand` that sets `source='rpc'`. The structured metadata comes from the request itself (entity type, operation, IDs) rather than parsing a command string, since the RPC layer already has typed arguments.

## Risks / Trade-offs

- **Large surface area** — ~100+ new endpoints is significant. Mitigated by mechanical mapping from the `Command` ADT and consistent patterns per domain group.
- **JSON schema drift** — CLI and server must agree on request/response types. Mitigated by sharing types in a common library.
- **Session state complexity** — Server-side session context adds statefulness. Mitigated by the existing session table and repo functions; context is already stored in `AppState`.
- **No auth yet** — RPC endpoints are unauthenticated until the Auth change. Acceptable for development; the server is not exposed publicly.
- **Test coverage** — Each new endpoint needs tests. Mitigated by following the pattern established in `ApiSpec.hs` with `servant-client` and `testWithApplication`.
