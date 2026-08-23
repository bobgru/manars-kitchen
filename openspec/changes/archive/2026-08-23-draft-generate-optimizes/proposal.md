## Why

`schedule create` is the only caller of `Service.Optimize.optimizeSchedule` (`src/CLI/App.hs:501`)
and the only place a `ProgressEvent` is ever published. Step 2 of item 1 in `docs/STATUS.md`
removes the whole named-schedule surface, `schedule create` included — which would silently
orphan `Service.Optimize`, `Domain.Optimizer`, and every requirement in the `progress-events`
capability.

`draft generate` is the surviving generator and it does not optimize: `generateDraft` calls
`buildScheduleFrom` once and saves the result. So the optimizer has to move to `draft generate`
*before* the named-schedule removal, not as part of it — otherwise there is an intermediate
commit in which the product has lost its optimizer.

Moving it is also a strict improvement independent of the removal: a draft has a real pay-period
window, station closures and prior calendar hours, so an optimized draft is better-informed than
an optimized named schedule ever was (`docs/adr/0001-drafts-supersede-named-schedules.md`).

## What Changes

- `Service.Draft.generateDraft` takes a `TopicBus ProgressEvent` and calls
  `Service.Optimize.optimizeSchedule` in place of `Domain.Scheduler.buildScheduleFrom`.
- The CLI's `[opt] phase=… iter=… unfilled=… score=… elapsed=…s` printer moves out of the
  `ScheduleCreate` arm into a shared `withProgressPrinting` helper, used by both
  `draft generate` and (until step 2 deletes it) `schedule create`.
- The REST and RPC generate handlers pass a bus with no subscribers, so progress is dropped —
  the behaviour the `progress-events` capability already specifies for that case.

No output changes by default: `cfgOptEnabled` defaults to `0.0`, and `optimizeSchedule` with
optimization disabled is exactly `buildScheduleFrom seed ctx`. The demo, whose stability rests
on that default, is unaffected.

## Capabilities

### Modified Capabilities
- `progress-events`: the CLI requirement names `schedule create` as the command that
  subscribes; it becomes `draft generate`.
- `draft-session`: `draft generate` runs the optimizer, not a single greedy pass.

## Impact

- **Service** (`src/Service/Draft.hs`): `generateDraft` gains a bus parameter; imports
  `Service.Optimize` and `Service.PubSub`.
- **CLI** (`src/CLI/App.hs`): new `withProgressPrinting` helper; `DraftGenerate` uses it.
- **Server** (`server/Server/Handlers.hs`, `server/Server/Rpc.hs`): each generate handler
  creates a subscriber-less bus.
- **Tests** (`test/DraftSpec.hs`): the one direct `generateDraft` call passes a bus.
- No DB schema change. No REST or RPC shape change. No frontend change.
