## Why

The scheduling system has a fully implemented and tested Hint system (`Domain/Hint.hs`) that provides in-memory, reversible "what-if" experiments for scheduling. It supports 6 hint types (CloseStation, PinAssignment, AddWorker, WaiveOvertime, GrantSkill, OverridePreference), accumulates hints in a session, recomputes the schedule on each change, and supports individual revert. However, this capability is completely inaccessible from the CLI. Exposing it within draft sessions (Change 2) gives users a lightweight exploration tool -- cheaper than checkpoints because hints are in-memory and semantic rather than database-level.

## What Changes

- **New `what-if` CLI command group** exposes all 6 hint types through natural-language commands within the REPL.
- **Hint session state** added to `AppState` -- an `IORef (Maybe Session)` that is active only within a draft session.
- **What-if commands**: `what-if close-station`, `what-if pin`, `what-if add-worker`, `what-if waive-overtime`, `what-if grant-skill`, `what-if override-prefs`.
- **Session management commands**: `what-if revert` (undo last), `what-if revert-all` (clear all), `what-if list` (show active hints).
- **Diff display**: After each hint add/revert, display a summary of what changed (assignments added/removed, unfilled positions gained/lost).
- **New `what-if apply` command** bridges from hypothetical to real: takes the most recent hint and executes the corresponding real mutation (e.g., `what-if grant-skill marco grill` followed by `what-if apply` runs `worker grant-skill marco grill` and regenerates the schedule).
- **Guard**: all `what-if` commands require an active draft session; outside a draft they display an error.
- Name-based entity resolution (existing) and session context / dot substitution (existing) work with `what-if` commands.

## Capabilities

### New Capabilities
- `hint-cli`: CLI exposure of the existing Hint system within draft sessions. Covers command parsing for all 6 hint types, hint session lifecycle (init/teardown tied to drafts), revert/list operations, diff display after each mutation, and the `what-if apply` bridge from hypothetical to real change.

### Modified Capabilities
- `two-level-help`: The `what-if` command group must appear in the help system with its own group and subcommand listings.
- `session-context`: Dot substitution and `use` context must resolve correctly in `what-if` command arguments (worker, station, skill positions).

## Impact

- **CLI/Commands.hs**: New `WhatIf*` command variants added to the `Command` type and `parseCommand` function.
- **CLI/App.hs**: New `asHintSession :: IORef (Maybe Session)` field in `AppState`. New handler functions for each what-if command. Guard logic checking for active draft. Diff computation and display after each hint operation.
- **CLI/Display.hs**: New `displayHintDiff` function showing before/after comparison of assignments and unfilled positions. New `displayHintList` for showing active hints in human-readable form.
- **CLI/Resolve.hs**: Entity resolution already supports worker, station, skill -- no changes needed, but what-if argument positions must be mapped to the correct entity kinds.
- **Domain/Hint.hs**: No changes. The domain layer is complete and tested.
- **Dependencies**: Primarily depends on draft-system (Change 2) for the draft session guard. Sequentially follows pay-periods (Change 6) in the roadmap but has no functional dependency on it.
