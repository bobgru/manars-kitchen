## 1. CLI Commands

- [ ] 1.1 Update `CLI/Commands.hs` constructors: change worker `Int` arg to `String` for: `WorkerGrantSkill`, `WorkerRevokeSkill`, `WorkerSetHours`, `WorkerSetOvertime`, `WorkerSetPrefs`, `WorkerSetShiftPref`, `WorkerSetVariety`, `WorkerSetWeekendOnly`, `WorkerSetStatus`, `WorkerSetOvertimeModel`, `WorkerSetPayTracking`, `WorkerSetTemp`, `WorkerSetSeniority`, `WorkerSetCrossTraining`, `WorkerClearCrossTraining`, `WorkerAvoidPairing`, `WorkerClearAvoidPairing`, `WorkerPreferPairing`, `WorkerClearPreferPairing`. Update station/skill args to `String` where they're currently `Int`/`SkillId`/`StationId` (e.g., grant-skill, revoke-skill, set-prefs, set-cross-training, clear-cross-training).
- [ ] 1.2 Update `CmdAssign` and `CmdUnassign` constructors so worker and station args are `String`.
- [ ] 1.3 Update `PinAdd` and `PinRemove` constructors so worker and station args are `String`.
- [ ] 1.4 Update `WhatIfPin`, `WhatIfWaiveOvertime`, `WhatIfGrantSkill`, `WhatIfOverridePrefs` constructors so worker arg is `String` (and skill/station args where applicable).
- [ ] 1.5 Update parser patterns in `CLI/Commands.hs`: remove `isDigit'` guards on the worker arg for the verbs above; capture the string directly. Verify `assign`/`unassign`/`pin`/`unpin`/`what-if` parsing keeps the same arity.
- [ ] 1.6 Update CLI executor in `App.hs` for each affected verb: at the start of the handler, call `Service.Worker.resolveWorkerByName (asRepo st) (T.pack name)`; on `Left WorkerNotFound n` print not-found; on `Left (NotAWorker n)` print "not a worker"; on `Right (wid, _)` proceed with the existing service call. Skill and station resolution is already handled by `Resolve.hs`; confirm the executor receives ids in numeric-string form there or call the relevant resolver explicitly.

## 2. CLI Resolve

- [ ] 2.1 Verify `Resolve.hs` `commandEntityMap` lists every command from §1 with `Resolve EWorker` (and `Resolve ESkill`, `Resolve EStation`, `ResolveRest EStation` as appropriate). Add any missing entries.
- [ ] 2.2 Confirm the resolver's worker name lookup uses the change-1 model (lookup `users.username`, return `users.id` as the resolved id-string). If it currently uses an older lookup, update it to delegate to `Service.Worker.resolveWorkerByName` (and emit the `WorkerId`'s integer as the resolved string).

## 3. REST API

- [ ] 3.1 Update `Server/Api.hs` route types: change every `Capture "id" Int` on a worker-keyed route to `Capture "name" Text` for routes: `/api/workers/:name/hours`, `/overtime`, `/prefs`, `/variety`, `/shift-prefs`, `/weekend-only`, `/seniority`, `/cross-training`, `/employment-status`, `/overtime-model`, `/pay-tracking`, `/temp`, `/avoid-pairing`, `/prefer-pairing`. The add/remove skill subroute also changes its skill capture from `SkillId` to `Text`.
- [ ] 3.2 Update affected handlers in `Server/Handlers.hs`: each handler swaps its `Int` parameter for `Text`, calls `resolveWorkerName repo name` (already imported from change 1), and continues with the resulting `WorkerId`. Skill name capture handlers resolve via the existing skill name resolution.
- [ ] 3.3 Update wiring order in `Server/Handlers.hs` if route ordering changes; otherwise wiring stays the same (handler argument types just shift from `Int` to `Text`).
- [ ] 3.4 Update `cli/CLI/RpcClient.hs` for any client functions that take a numeric worker id; they take a `Text` name now. The previous change stubbed several worker-related branches as "not yet supported in remote mode" — these stubs continue to apply where the local CLI is sufficient.

## 4. Tests

- [ ] 4.1 Update `test/ApiSpec.hs`: every call site that uses a numeric worker id in a path swaps to the test user's username (e.g., `setWorkerHoursC 2 ...` → `setWorkerHoursC "worker1" ...`). The `c*C` client typedefs auto-update from the `Server.Api` route changes; verify the typecheck.
- [ ] 4.2 Update tests that expect specific `Int` types in service-level calls (none expected — service signatures unchanged).

## 5. Demo and Audit

- [ ] 5.1 Inspect `demo/restaurant-setup.txt` for any remaining numeric `<wid>` uses on the affected verbs; replace with names. The demo already uses names for most worker verbs.
- [ ] 5.2 Verify `Audit/CommandMeta.hs` classifier still classifies the new command shapes correctly (verb names unchanged; `cmEntityId` may now be `Nothing` since the params arrive as names — acceptable; the `command` text still has the resolvable name).

## 6. Verify

- [ ] 6.1 `stack clean`, then `stack build` and fix all warnings.
- [ ] 6.2 `stack test` and fix failures.
- [ ] 6.3 `make fast-demo` and verify it runs to completion.
- [ ] 6.4 Manual smoke test through the CLI: `worker grant-skill alice grill`, `worker set-hours alice 40`, `pin alice grill monday 9`, `assign april alice grill 2026-04-06 9`, `what-if grant-skill alice prep`. Each should resolve names and produce the expected outputs.
- [ ] 6.5 Manual REST smoke test via curl for at least one of the renamed routes (e.g., `PUT /api/workers/alice/hours`).
