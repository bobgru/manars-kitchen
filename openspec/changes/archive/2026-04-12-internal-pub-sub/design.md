## Context

The optimizer (`Service.Optimize`) accepts a progress callback `(OptProgress -> IO ())` threaded through its recursive loop. The CLI wires this directly at the call site in `CLI.App`. This works for a single consumer, but the web interface roadmap requires multiple simultaneous consumers (SSE to browser, CLI output) and graceful no-op when nobody is listening. Other long-running operations (draft generation, hint rebase, audit replay) will need progress reporting too, and duplicating the callback-threading pattern in each would be tedious.

The codebase currently has no STM usage and no `stm` dependency. All I/O is sequential within each CLI command.

## Goals / Non-Goals

**Goals:**
- Provide a reusable in-process event bus that service-layer code can publish to without knowing who (if anyone) is listening.
- Support zero, one, or many concurrent subscribers per bus.
- Drop events silently when no subscribers exist (fire-and-forget).
- Refactor the optimizer to publish through the bus, removing its callback parameter.
- Keep the implementation minimal — this is plumbing, not a framework.

**Non-Goals:**
- Persistence or replay of events (events are ephemeral progress feedback).
- Cross-process or networked pub/sub (this is in-process only; SSE bridging comes later).
- Backpressure or bounded queues (events are small and infrequent thanks to existing throttling).
- Adding progress events to draft generation, hint rebase, or audit replay (future changes will do this; we only wire up the optimizer now).

## Decisions

### Callback-list approach over STM TChan

Use an `MVar` holding a map of subscription IDs to callback functions (`event -> IO ()`). Publishing iterates the map and calls each handler. Subscribing inserts; unsubscribing removes.

**Why not TChan:** TChan requires adding `stm` as a dependency and introduces broadcast-channel semantics that are more machinery than needed. The callback approach maps directly to the existing pattern (the optimizer already calls a function), just generalizing from one callback to zero-or-many. If we later need buffering or async delivery, we can swap internals without changing the API.

**Why MVar over IORef:** While current usage is single-threaded, the bus handle will be shared across the service layer. MVar provides safe concurrent access at negligible cost and prevents future bugs if threading is introduced.

### Typed bus with a single event type parameter

`PubSub e` is parameterized over the event type. The service layer will use `PubSub ProgressEvent` where `ProgressEvent` is a sum type covering all operation kinds. A single bus per session keeps things simple; multiple buses per event type is possible but unnecessary now.

### ProgressEvent as a sum type wrapping existing OptProgress

Rather than replacing `OptProgress`, wrap it: `ProgressEvent = OptimizeProgress OptProgress | ...`. Future variants (e.g., `DraftProgress`, `RebaseProgress`) extend the sum type without touching the optimizer. Consumers pattern-match on what they care about.

### Throttling stays in the optimizer

The existing `maybeReport` throttle logic remains in `Service.Optimize`. The bus is dumb plumbing — it delivers every event it receives. Throttling is the publisher's concern because optimal intervals vary by operation type.

### Bus handle threaded via a service context record

Add a `PubSub ProgressEvent` field to a `ServiceContext` record (or equivalent) that service functions receive. This avoids threading the bus as an extra parameter to every function. The CLI creates the bus, builds the context, and subscribes before calling service operations.

## Risks / Trade-offs

**[Synchronous callbacks block the publisher]** → Callbacks run in the publisher's thread. A slow subscriber (e.g., network write) would block the optimization loop. Acceptable for CLI (stdout is fast) and tolerable for now. If SSE delivery becomes slow, wrap the callback in `forkIO` at the subscriber's discretion — the bus itself stays simple.

**[No ordering guarantees across subscribers]** → Subscribers are called in map-iteration order, which is arbitrary. Fine for independent consumers (CLI and SSE don't coordinate).

**[Breaking change to optimizeSchedule signature]** → Removing the callback parameter is a breaking change to the internal API. Only two call sites exist (CLI.App and the test suite), so the migration is trivial.
