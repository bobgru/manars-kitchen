## Why

The optimizer already reports progress via a callback parameter (`OptProgress -> IO ()`), but this pattern is ad-hoc — wired directly from the CLI's REPL loop into `optimizeSchedule`. Other long-running operations (draft generation, hint session rebase, audit replay) have no progress reporting at all. As the system gains an HTTP layer with SSE streaming and a browser-based admin UI, we need a uniform way for service-layer operations to emit progress events that multiple consumers (CLI, SSE, or nothing) can independently subscribe to — without the service code knowing who's listening.

## What Changes

- Introduce a `PubSub` module providing a typed, in-process event bus: create a bus, subscribe, publish, unsubscribe.
- Events published with no subscribers are silently dropped (fire-and-forget).
- Define a `ProgressEvent` sum type covering the event kinds the service layer will emit (optimization progress, draft generation steps, hint rebase steps, audit replay steps).
- Refactor `Service.Optimize` to publish `ProgressEvent` values through the bus instead of accepting a raw callback parameter.
- Thread a `PubSub` handle through the service layer so future services can publish without API changes.

## Capabilities

### New Capabilities
- `pub-sub-bus`: In-process typed publish/subscribe bus with subscribe, publish, unsubscribe, and fire-and-forget semantics
- `progress-events`: Typed progress event definitions and integration of the bus into the service layer, starting with the optimizer

### Modified Capabilities

## Impact

- `Service.Optimize` loses its `(OptProgress -> IO ())` callback parameter; callers subscribe to the bus instead.
- `cli/CLI/App.hs` changes where it calls `optimizeSchedule` — subscribes to the bus before the call, unsubscribes after.
- A `PubSub` handle becomes part of the service-layer context, threaded alongside `Repository`.
- No database changes. No new dependencies beyond `stm` (likely already available via GHC).
