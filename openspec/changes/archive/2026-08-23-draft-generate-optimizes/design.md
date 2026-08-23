## Context

Two facts drive the whole design:

1. `optimizeSchedule ctx seed bus` short-circuits to `return (buildScheduleFrom seed ctx)`
   when `cfgOptEnabled cfg <= 0.0`, and `defaultSchedulerConfig` sets `cfgOptEnabled = 0.0`
   (`src/Domain/SchedulerConfig.hs:95`). Swapping the call in `generateDraft` is therefore a
   no-op for every existing caller, test and demo run until someone runs
   `config set opt-enabled 1`.
2. `optimizeSchedule` is in `IO` (it needs `newStdGen` and wall-clock throttling) whereas
   `buildScheduleFrom` is pure. `generateDraft` is already in `IO`, so no signature colour
   change is needed — only the extra bus argument.

## Goals / Non-Goals

**Goals**
- `draft generate` gains optimization, with the same throttled `[opt]` progress output that
  `schedule create` produced.
- `Service.Optimize`, `Domain.Optimizer` and the `progress-events` capability keep exactly one
  live producer and one live consumer, so step 2's removal orphans nothing.

**Non-Goals**
- Streaming optimizer progress to the browser over SSE. The REST and RPC handlers pass a
  subscriber-less bus. Progress over SSE would need a per-request correlation id and a new
  event kind in `eventVisibleTo`; that is its own change.
- Turning optimization on by default. `cfgOptEnabled` stays `0.0`. A 30-second default time
  limit (`cfgOptTimeLimitSecs = 30.0`) on a synchronous REST handler is not something to
  enable by side effect.

## Decisions

### The bus is a parameter, not something `generateDraft` creates

`generateDraft` could create its own bus internally and expose a
`Maybe (OptProgress -> IO ())` callback instead. Rejected: `progress-events` deliberately
replaced a callback with a bus, and the bus is what lets the CLI attach and detach a printer
around the call without the service layer knowing what a printer is. Passing the bus in also
leaves the door open for the server to attach a subscriber later without touching
`Service.Draft` again.

### The `[opt]` printer becomes a helper, not a copy

`withProgressPrinting :: (TopicBus ProgressEvent -> IO a) -> IO a` creates the bus,
subscribes the printer, runs the action and unsubscribes. Both `draft generate` and
`schedule create` use it for the duration of this change; step 2 deletes the `schedule create`
call site and the helper stays with one caller. Duplicating the 12-line printer into the
`DraftGenerate` arm would leave two copies to keep in sync for exactly one commit, and would
make step 2's diff look like it was deleting the printer.

### REST and RPC drop progress rather than buffering it

Both handlers are synchronous request/response — there is nowhere to put interim progress. The
`progress-events` spec already has a "Optimizer with no subscriber" scenario stating the run
completes normally and events are silently dropped, so a bare `newTopicBus` is the specified
behaviour, not a shortcut.

### Rejected: delete the optimizer along with named schedules

The alternative reading of STATUS step 2 is that the optimizer is part of the named-schedule
surface and goes with it. Rejected: nothing about the optimizer is named-schedule-specific — it
takes a `SchedulerContext` and a seed `Schedule`, both of which `generateDraft` already builds,
and builds them *better* (real pay-period bounds, station closures, calendar hours). Deleting
209 lines of working optimizer plus `Domain.Optimizer` to avoid a signature change is the wrong
trade.

### Rejected: leave the optimizer orphaned and unreferenced

`-Wall` does not warn about an exported library module with no call sites, so this would
compile clean — and that is the problem. `progress-events` would become a capability with no
implementation and no test, discoverable only by reading it.

## Risks / Trade-offs

- **A user who sets `opt-enabled 1` now blocks a REST generate request for up to
  `opt-time-limit-secs`.** That was already true of the CLI path. Mitigation: the default stays
  off, and the risk is noted here rather than fixed, because fixing it means asynchronous
  generate — a much larger change.
- **`generateDraft`'s arity grows.** Four call sites, all updated in this change; the compiler
  finds any that are missed.

## Discovered while implementing: the optimizer diverges on weekends

Wiring the optimizer into a path that has tests exposed a defect that `schedule create` had
been hiding. With `opt-enabled > 0`, a date range containing a Saturday never returns: the
process allocates about 1 GB/s until the OOM killer ends it. Measured against a
one-station, nine-worker fixture (`test/DraftSpec.hs`):

| range | result |
| --- | --- |
| Apr 6–10 2026 (Mon–Fri) | returns at the 1s limit |
| Apr 13–17 2026 (Mon–Fri) | returns at the 1s limit |
| Apr 6–12 2026 (Mon–Sun) | OOM-killed after ~17s / 17 GB |
| Apr 11 2026 alone (Sat) | OOM-killed |

So it is the presence of a Saturday, not the size of the range. Setting
`opt-time-limit-secs` to `0.0001` — which makes `hardPhase` return on its first clock check,
before any `iteratedGreedyStep` call — lets a full week finish in 0.12s, and `bestOfStrategies`
runs all five greedy strategies at magnitude 0 over that same week without trouble. The
divergence is therefore inside `iteratedGreedyStep`'s perturbed rebuild
(`buildScheduleFromPerturbed` with a non-zero magnitude), on the weekend-constraint path, and
the time limit cannot interrupt it because it is only checked between iterations.

This change does **not** fix it. It is pre-existing, it is unreachable at the default
`opt-enabled` of `0`, and it lives in `Domain.Scheduler`/`Domain.Optimizer` rather than in
anything this change touches — diagnosing which of the five strategies diverges and why needs
its own change. What this change does is stop it being invisible: the reproduction is recorded
in `docs/STATUS.md` and as a `pending` test, so the next person to reach for `opt-enabled` finds
it before their server does.

The alternative — fixing it here so that "draft generate optimizes" is true for real date
ranges — was rejected on scope. `opt-enabled` was already 0 and already unusable on a week
before this change; shipping the move does not make anything worse, and holding the move
hostage to a scheduler investigation blocks the named-schedule removal behind it.
