## Context

The scheduling system has a complete Hint domain layer (`Domain/Hint.hs`) providing in-memory, reversible "what-if" experiments. A `Session` holds the original `SchedulerContext`, an ordered list of `Hint` values, and a recomputed `ScheduleResult`. Hints can be added, reverted individually, or reverted to a specific step. On each mutation the entire schedule is rebuilt from scratch via `buildScheduleFrom`.

The CLI (`CLI/App.hs`) manages state through `AppState`, which holds the repository, authenticated user, session context (`IORef SessionContext`), and checkpoint stack (`IORef [String]`). Commands are parsed by `CLI/Commands.hs` into a `Command` ADT and dispatched in `handleCommand`. Entity resolution (`CLI/Resolve.hs`) translates names and dot-placeholders into IDs before command parsing.

This change adds hint session management to the CLI, exposing the domain layer through `what-if` commands. The hint session is tied to draft sessions (Change 2) -- this design assumes drafts will add a `asDraft :: IORef (Maybe DraftState)` field or similar, and hints gate on that being active.

## Goals / Non-Goals

**Goals:**
- Expose all 6 hint types through intuitive `what-if` CLI commands
- Show a meaningful diff after each hint operation (what assignments changed, what unfilled positions changed)
- Provide `what-if apply` to bridge from hypothetical exploration to real mutation
- Integrate with existing name resolution and session context
- Gate hint commands on an active draft session

**Non-Goals:**
- Incremental schedule recomputation (hints always recompute from scratch; optimization is a future concern)
- Persistence of hint sessions across REPL restarts (hints are in-memory only)
- Draft system implementation (Change 2 prerequisite; this change assumes drafts exist)
- Changes to `Domain/Hint.hs` (the domain layer is complete)
- Multi-user hint sessions or shared exploration

## Decisions

### Hint session state lives in AppState as IORef (Maybe Session)

A new field `asHintSession :: IORef (Maybe Session)` is added to `AppState`. `Nothing` means no active hint session. When a draft session begins, the hint session can be initialized via `what-if` commands (lazy init on first `what-if` use, building the `SchedulerContext` from the current draft state). When the draft ends, the hint session is cleared.

**Alternative considered:** Store the hint session inside the draft state. Rejected because hints and drafts have different lifecycles -- a user might start and clear multiple hint explorations within a single draft.

### Lazy initialization of hint session

The hint `Session` is created on the first `what-if` command rather than when the draft opens. This avoids an upfront scheduler run if the user never uses hints. The initialization loads the current `SchedulerContext` from the repository (same as `schedule create` does) and calls `newSession` from `Domain/Hint.hs`.

**Alternative considered:** Eager init when draft opens. Rejected because building a `SchedulerContext` and running the scheduler has a cost, and many draft sessions may not use hints.

### Command parsing uses "what-if" prefix with subcommands

All hint commands start with `what-if` followed by a subcommand:
- `what-if close-station <station> <day> <hour>`
- `what-if pin <worker> <station> <day> <hour>`
- `what-if add-worker <name> <skills...> [hours]`
- `what-if waive-overtime <worker>`
- `what-if grant-skill <worker> <skill>`
- `what-if override-prefs <worker> <stations...>`
- `what-if revert`
- `what-if revert-all`
- `what-if list`
- `what-if apply`

The `what-if` prefix is treated as a single command group token in the parser. Because `words` tokenization splits on whitespace, `what-if` is parsed as two tokens `["what-if", ...]` in the word list, but the parser matches on the combined prefix.

**Alternative considered:** Single-word prefix like `hint` or `whatif`. Rejected because `what-if` reads naturally and matches the conceptual model -- the hyphen makes it parseable as a single logical prefix despite being one token in `words`.

### Diff display shows before/after summary

After each `addHint` or `revertHint`, the system computes the difference between the old and new `ScheduleResult`:
- Assignments added (present in new, absent in old)
- Assignments removed (present in old, absent in new)
- Unfilled positions gained (unfilled in new, not in old)
- Unfilled positions resolved (unfilled in old, not in new)

This is computed by set-differencing `unSchedule` of old and new results, and list-differencing `srUnfilled`. Display uses existing worker/station name maps for readable output.

**Alternative considered:** Show the full schedule after each hint. Rejected because full schedules are large and the user wants to see the effect of their change, not the entire state.

### "what-if apply" translates the last hint to a real command

`what-if apply` examines the most recent hint in the session and executes the corresponding real mutation:
- `GrantSkill w sk` -> `worker grant-skill <w> <sk>` (calls `SW.grantWorkerSkill`)
- `WaiveOvertime w` -> `worker set-overtime <w> on` (calls `SW.setOvertimeOptIn`)
- `OverridePreference w prefs` -> `worker set-prefs <w> <prefs...>` (calls `SW.setStationPreferences`)
- `AddWorker` -> requires creating a user first (complex; initially unsupported, display message suggesting manual creation)
- `CloseStation` -> no direct equivalent; display the station close-day command if applicable, or explain it's a slot-level operation
- `PinAssignment` -> `pin <w> <s> <day> <hour>` (calls `SW.addPin`)

After applying, the hint is removed from the session and the session is recomputed from the updated context. Not all hints are directly applicable (e.g., `CloseStation` at a specific slot has no persistent equivalent), so `apply` must handle this gracefully.

**Alternative considered:** Apply all hints at once. Rejected because the user may want some hints as permanent changes and others as temporary exploration. One-at-a-time gives control.

### Draft session guard

All `what-if` commands check for an active draft session before proceeding. Without a draft, they display: "No active draft. Start a draft session first." This ensures hints operate on a well-defined scheduling context.

Until Change 2 (draft system) is implemented, the guard can be stubbed to always pass (or hints can work against the current repository state directly). The design accommodates both approaches.

## Risks / Trade-offs

**[Risk] Schedule recomputation is O(full schedule) on each hint** -- For a restaurant with ~12 workers and weekly slots (~60-80 slots), recomputation takes milliseconds. For monthly schedules (~240-320 slots), it could take seconds. The optimizer adds further time.
-> Mitigation: Use `buildScheduleFrom` (non-optimized) for hint recomputation rather than `optimizeSchedule`. Hints are for quick exploration, not production-quality schedules. Display a timing notice if recomputation exceeds 1 second.

**[Risk] `what-if apply` has incomplete coverage** -- Not all hint types have direct persistent equivalents (e.g., `CloseStation` at a specific slot, `AddWorker` for temp workers).
-> Mitigation: `apply` clearly communicates what it can and cannot do. For unsupported types, it suggests the manual steps. This is honest UX rather than failing silently.

**[Risk] Hint session becomes stale if draft is modified** -- If the user makes real changes to the draft (e.g., adds a worker) while hints are active, the hint session's `sessOrigCtx` is outdated.
-> Mitigation: After any mutating command within a draft, clear the hint session and notify the user: "Hint session cleared due to data change. Use what-if commands to start a new exploration." This is simpler than trying to update the session incrementally.

**[Risk] Dependency on draft system (Change 2)** -- This change requires drafts to exist for the guard logic.
-> Mitigation: Design the guard as a simple boolean check (`hasDraft :: AppState -> IO Bool`). Before Change 2 is implemented, this can return `True` always (allow hints globally) or `False` always (disable hints). The hint logic itself is independent of draft internals.
