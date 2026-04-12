## Why

The web interface roadmap (step 5) requires that every CLI command be callable over HTTP so the CLI can operate as a thin client against a remote server. The REST API currently covers ~20 endpoints but the CLI exposes ~140 commands. The RPC-over-REST layer bridges this gap: each CLI command maps 1:1 to an RPC endpoint implemented as a sequence of REST calls. This keeps the REST API as the real contract while giving the CLI a single HTTP translation point.

## What Changes

- Introduce an RPC endpoint layer where each CLI command has a corresponding `/rpc/<command>` POST endpoint that accepts command arguments as JSON and returns the command result as JSON.
- Each RPC handler is implemented by composing calls to existing REST API endpoints (and new ones where needed), not by calling service functions directly.
- Extend the REST API with additional endpoints to cover operations not yet exposed (admin CRUD for skills/stations/shifts/workers, pin management, import/export, audit log, checkpoint operations, calendar mutations, hint sessions, config writes).
- Add a `CommandClassifier`-compatible audit trail so RPC calls are logged identically to direct CLI invocations.
- Provide a client module that the CLI can use to dispatch commands over HTTP instead of calling service functions directly.

## Capabilities

### New Capabilities
- `rpc-command-dispatch`: Maps CLI `Command` ADT constructors 1:1 to RPC POST endpoints under `/rpc/`, with JSON request/response encoding for each command
- `rpc-client`: Client module that the CLI imports to dispatch commands over HTTP, replacing direct service-layer calls when running in remote mode

### Modified Capabilities
- `rest-api-endpoints`: Add REST endpoints for operations not yet exposed — admin entity CRUD, pins, calendar mutations, audit log, checkpoints, config writes, hint sessions, import/export — so the RPC layer can compose against them

## Impact

- New `server/Server/Rpc.hs` module defining RPC endpoint types and handlers.
- New `cli/CLI/RpcClient.hs` module providing the HTTP dispatch client.
- `Server.Api` and `Server.Handlers` grow significantly with ~30-40 new REST endpoints.
- `Server.Json` gains request/response types for all new endpoints.
- New dependencies: possibly `servant-client` in the CLI executable for type-safe HTTP calls.
- Audit logging must cover RPC-originated commands with the same structured metadata as CLI-originated ones.
- No changes to the domain layer or service layer — all new code is in the server and CLI layers.
