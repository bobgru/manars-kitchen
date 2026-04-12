## Context

The system has a well-tested service layer (Service.Worker, Service.Schedule, Service.Draft, Service.Calendar, Service.Absence, Service.Config) accessed exclusively through the CLI. The web interface roadmap requires an HTTP API as the foundation for browser clients and the future RPC-over-REST layer. The repository uses a record-of-functions pattern (`Repo.Types.Repository`), making it straightforward to thread through handlers.

## Goals / Non-Goals

**Goals:**
- Expose all service-layer operations as REST endpoints with JSON request/response bodies.
- Map service-layer errors (Nothing, Left) to appropriate HTTP status codes (400, 404, 409, 500).
- Provide a standalone server executable with configurable database path and port.
- Cover the HTTP layer with integration tests that verify routing, serialization, and error handling.

**Non-Goals:**
- Authentication or authorization (deferred to roadmap step 7).
- RPC translation layer for the CLI (deferred to roadmap step 5).
- SSE or WebSocket support for progress streaming (future work).
- Re-testing domain logic through the API (the service layer already has 479 tests).

## Decisions

### Servant for the API type

Servant's type-level API definition provides compile-time guarantees that handlers match routes, and enables deriving type-safe client functions for tests. This eliminates an entire class of routing bugs and makes the test suite trivial to write — `client api` produces one function per endpoint.

### Orphan JSON instances in a dedicated module

Domain types (WorkerId, Slot, Assignment, Schedule, etc.) live in the library and shouldn't depend on `aeson`. Orphan ToJSON/FromJSON instances are collected in `Server.Json` with `-Wno-orphans`. This keeps the domain pure while providing the serialization the HTTP layer needs.

### Handlers as thin wrappers with Repository closure

Each handler takes `Repository` as its first argument and calls the corresponding service function. The `server` function partially applies `Repository` to all handlers. No ReaderT, no monad transformer stack — just plain `Handler` with `liftIO` for service calls. This matches the existing pattern where the CLI threads `Repository` through commands.

### Error mapping via ApiError ADT

A small `Server.Error` module defines `ApiError` (NotFound, BadRequest, Conflict, InternalError) and `throwApiError` which converts these to Servant's `ServerError` with a JSON body `{"error": "message"}`. Handlers pattern-match on service results (Nothing → NotFound, Left msg → appropriate error).

### In-process testing with servant-client

Tests use `testWithApplication` from warp to run the WAI app on an ephemeral port, and `servant-client` to derive type-safe client functions from the same API type. Each test gets a fresh temporary SQLite database. This tests the full HTTP stack (serialization, routing, status codes) without external processes.

## Risks / Trade-offs

**[Orphan instances can conflict]** → If another module defines ToJSON/FromJSON for the same types, GHC will report overlapping instances. Mitigated by keeping all HTTP-layer instances in one module and noting the pattern in the pragma.

**[No auth on endpoints]** → All endpoints are currently unprotected. Acceptable for development; auth is roadmap step 7.

**[Synchronous handlers]** → All handlers block on IO. For the current single-user scenario this is fine. If concurrent load becomes relevant, the handler pattern doesn't change — warp already handles concurrency.
