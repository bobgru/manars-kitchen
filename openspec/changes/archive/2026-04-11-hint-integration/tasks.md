## 1. Command Parsing

- [x] 1.1 Add `WhatIfCloseStation`, `WhatIfPin`, `WhatIfAddWorker`, `WhatIfWaiveOvertime`, `WhatIfGrantSkill`, `WhatIfOverridePrefs` command variants to `Command` ADT in `CLI/Commands.hs`
- [x] 1.2 Add `WhatIfRevert`, `WhatIfRevertAll`, `WhatIfList`, `WhatIfApply` command variants to `Command` ADT
- [x] 1.3 Add `parseCommand` patterns for all `what-if` subcommands matching the word-list prefix `["what-if", ...]`
- [x] 1.4 Verify name-based entity resolution works with what-if commands (worker, station, skill argument positions map correctly through `resolveInput`)

## 2. App State

- [x] 2.1 Add `asHintSession :: IORef (Maybe Session)` field to `AppState` in `CLI/App.hs`
- [x] 2.2 Update `mkAppState` to initialize the hint session IORef to `Nothing`
- [x] 2.3 Add `hasDraft :: AppState -> IO Bool` guard function (stub returning `True` until draft system is implemented)
- [x] 2.4 Add hint session clearing logic: after any mutating command within a draft, clear the hint session IORef and print notification if it was active

## 3. Hint Session Initialization

- [x] 3.1 Implement `initHintSession :: AppState -> IO Session` that loads the current `SchedulerContext` from the repository (reusing logic from `ScheduleCreate` handler) and calls `newSession`
- [x] 3.2 Implement lazy init: on first what-if command, check if `asHintSession` is `Nothing`; if so, call `initHintSession` and store the result

## 4. Diff Display

- [x] 4.1 Implement `diffScheduleResults :: ScheduleResult -> ScheduleResult -> (Set Assignment, Set Assignment, [Unfilled], [Unfilled])` computing added/removed assignments and gained/resolved unfilled positions
- [x] 4.2 Implement `displayHintDiff` in `CLI/Display.hs` that renders the diff using worker/station name maps for human-readable output
- [x] 4.3 Handle the "no changes" case: display "No schedule changes." when diff is empty

## 5. Hint Command Handlers

- [x] 5.1 Implement `handleWhatIfCloseStation` -- parse station/day/hour, construct `CloseStation` hint, call `addHint`, display diff
- [x] 5.2 Implement `handleWhatIfPin` -- parse worker/station/day/hour, construct `PinAssignment` hint, call `addHint`, display diff
- [x] 5.3 Implement `handleWhatIfAddWorker` -- parse name/skills/optional hours, generate temp WorkerId, construct `AddWorker` hint, call `addHint`, display diff
- [x] 5.4 Implement `handleWhatIfWaiveOvertime` -- parse worker, construct `WaiveOvertime` hint, call `addHint`, display diff
- [x] 5.5 Implement `handleWhatIfGrantSkill` -- parse worker/skill, construct `GrantSkill` hint, call `addHint`, display diff
- [x] 5.6 Implement `handleWhatIfOverridePrefs` -- parse worker/stations, construct `OverridePreference` hint, call `addHint`, display diff

## 6. Session Management Handlers

- [x] 6.1 Implement `handleWhatIfRevert` -- call `revertHint` on session, display diff, report remaining hint count
- [x] 6.2 Implement `handleWhatIfRevertAll` -- call `revertTo 0` on session, display diff, report count reverted
- [x] 6.3 Implement `handleWhatIfList` -- display numbered list of active hints in human-readable form using entity names

## 7. What-If Apply

- [x] 7.1 Implement `handleWhatIfApply` -- examine last hint, dispatch to appropriate real mutation
- [x] 7.2 Handle `GrantSkill` apply: call `SW.grantWorkerSkill`, confirm
- [x] 7.3 Handle `WaiveOvertime` apply: call `SW.setOvertimeOptIn`, confirm
- [x] 7.4 Handle `OverridePreference` apply: call `SW.setStationPreferences`, confirm
- [x] 7.5 Handle `PinAssignment` apply: call `SW.addPin`, confirm
- [x] 7.6 Handle unsupported apply types (`AddWorker`, `CloseStation`): display informative message with suggested manual steps
- [x] 7.7 After successful apply, remove the applied hint, rebuild session from updated context

## 8. Help Integration

- [x] 8.1 Add `("what-if", "What-if hint exploration within drafts")` to `helpGroups` in `CLI/App.hs`
- [x] 8.2 Add help entries for all what-if subcommands to `helpRegistry` with syntax and descriptions
- [x] 8.3 Mark what-if commands as admin-only (since they operate within draft sessions which require admin)

## 9. REPL Dispatch

- [x] 9.1 Add what-if command cases to `handleCommand` in `CLI/App.hs` with draft guard check
- [x] 9.2 Add what-if commands to `isMutating` function (what-if commands are non-mutating since they only affect in-memory state; but `what-if apply` is mutating)
- [x] 9.3 Ensure what-if commands go through entity resolution path (not the quick-parse bypass) so dot substitution and name resolution work

## 10. Testing

- [x] 10.1 Add unit tests for `what-if` command parsing in `CLI/Commands.hs` -- all subcommands parse correctly
- [x] 10.2 Add unit tests for `diffScheduleResults` -- verify correct identification of added/removed assignments and gained/resolved unfilled
- [x] 10.3 Add integration test: full what-if workflow (add hint, verify diff, revert, verify restoration)
- [x] 10.4 Add test for `what-if apply` on a GrantSkill hint -- verify the skill is persisted and session is rebuilt
- [x] 10.5 Add test for hint session clearing on mutating command
- [x] 10.6 Add test for draft guard -- what-if commands rejected when no draft is active
