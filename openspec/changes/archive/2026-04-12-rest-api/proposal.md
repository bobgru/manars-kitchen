## Why

The web interface roadmap (step 4) requires an HTTP API that all browser-based clients and the future RPC layer will call. The service layer is well-tested and stable — what's missing is the HTTP surface that exposes it. Without it, only the CLI can interact with the system.

## What Changes

- Introduce a `servant`-based REST API with 20 endpoints under `/api/` covering skills, stations, shifts, schedules, drafts, calendar, absences, and scheduler config.
- Add a `server/` source directory containing the API type definition, JSON serialization (orphan instances for domain types plus request/response DTOs), handler implementations, and error mapping.
- Add a `manars-server` executable that starts a Warp HTTP server backed by a SQLite repository.
- Add a comprehensive API test suite (`test/ApiSpec.hs`) using `servant-client` and `testWithApplication` for in-process HTTP testing.

## Capabilities

### New Capabilities
- `rest-api-endpoints`: Type-safe HTTP API with 20 endpoints, JSON serialization for all domain types, and structured error responses (400/404/409/500)
- `rest-api-server`: Standalone Warp-based HTTP server executable with configurable database path and port

### Modified Capabilities

## Impact

- New `server/` directory with four modules: `Server.Api`, `Server.Json`, `Server.Handlers`, `Server.Error`.
- New `manars-server` executable stanza in `manars-kitchen.cabal`.
- New dependencies: `servant`, `servant-server`, `warp`, `wai`, `http-types`.
- Test suite gains `servant-client`, `http-client`, `http-types` dependencies and a `server` source directory.
- 19 new API tests added to the test suite.
- No changes to the domain layer or existing service layer. Handlers are thin wrappers that call existing service functions.
