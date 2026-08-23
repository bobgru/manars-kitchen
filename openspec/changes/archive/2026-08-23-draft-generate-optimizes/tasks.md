## 1. Service layer

- [x] 1.1 `src/Service/Draft.hs`: import `Service.Optimize (optimizeSchedule)` and
  `Service.PubSub (TopicBus, ProgressEvent)`.
- [x] 1.2 `generateDraft` gains a trailing `TopicBus ProgressEvent` parameter.
- [x] 1.3 Replace `let result = buildScheduleFrom seed ctx` with
  `result <- optimizeSchedule ctx seed bus`; drop the now-unused `buildScheduleFrom` import if
  nothing else in the module uses it.

## 2. CLI

- [x] 2.1 `src/CLI/App.hs`: add `withProgressPrinting :: (TopicBus ProgressEvent -> IO a) -> IO a`
  holding the bus creation, the `[opt]` printer subscription and the unsubscribe.
- [x] 2.2 Rewrite the `ScheduleCreate` arm to call `withProgressPrinting` instead of inlining
  the bus wiring.
- [x] 2.3 Wrap the `DraftGenerate` arm's `Draft.generateDraft` call in `withProgressPrinting`.

## 3. Server

- [x] 3.1 `server/Server/Handlers.hs`: `handleGenerateDraft` creates a `newTopicBus` and passes
  it to `SD.generateDraft`.
- [x] 3.2 `server/Server/Rpc.hs`: same for the `rpc/draft/generate` handler.

## 4. Tests

- [x] 4.1 `test/DraftSpec.hs`: the direct `Draft.generateDraft` call passes a `newTopicBus`.
- [x] 4.2 New unit test: with `opt-enabled` at 0, `generateDraft` publishes nothing to the bus.
- [x] 4.3 New unit test: with `opt-enabled` at 1 and a short `opt-time-limit-secs`,
  `generateDraft` fills a Mon–Fri draft and returns (assert on the saved assignments, not on
  event count — reporting is wall-clock throttled and a fast run legitimately emits nothing).
- [x] 4.4 New `pending` test recording the weekend divergence found while implementing, with
  the measurements from `design.md`.

## 5. Specs

- [x] 5.1 `openspec/specs/progress-events/spec.md`: the CLI-subscribes requirement names
  `draft generate`.
- [x] 5.2 `openspec/specs/draft-session/spec.md`: `draft generate` runs the optimizer.

## 6. Verification

- [x] 6.1 `stack clean && stack build --test` with zero warnings.
- [x] 6.2 `stack test` — integration and unit suites pass.
- [x] 6.3 Demo run exits 0 and `demo-export.json` is unchanged.
- [x] 6.4 Record the weekend divergence in `docs/STATUS.md` as a known defect with its
  reproduction.
- [x] 6.5 Archive this change to `openspec/changes/archive/`.
