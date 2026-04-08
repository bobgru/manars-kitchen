## 1. Two-Level Help

- [x] 1.1 Define a help registry data structure: list of `(group, isAdmin, commandSyntax, description)` tuples in `CLI/App.hs` (or a new `CLI/Help.hs` module), covering all existing commands organized into groups (schedule, worker, skill, station, shift, absence, config, pin, export, audit, general)
- [x] 1.2 Add `HelpGroup String` command variant to `CLI/Commands.hs` and parse `help <group>` in `parseCommand`
- [x] 1.3 Rewrite `printHelp` to use the registry: no-arg `help` prints group summaries; `help <group>` filters and prints commands for that group, respecting admin role filtering
- [x] 1.4 Test: verify `help` shows groups, `help schedule` shows only schedule commands, `help bogus` shows error with valid group names

## 2. Name-Based Entity Resolution

- [x] 2.1 Define a `RawCommand` type (or modify `Command` to use `Either String Int` for entity references) that allows tokens to remain unresolved after parsing
- [x] 2.2 Implement `resolveEntityRef :: Repository -> EntityType -> String -> IO (Either String Int)` that checks if token is numeric (return as ID) or looks up by name (case-insensitive) from the appropriate repo list function
- [x] 2.3 Implement `resolveCommand :: Repository -> RawCommand -> IO Command` that resolves all entity references in a raw command, returning errors for unresolvable names
- [x] 2.4 Update `parseCommand` to produce `RawCommand` instead of `Command`, keeping string tokens for entity references instead of `read`-ing them
- [x] 2.5 Wire resolution into the REPL loop: `parseCommand` -> `resolveCommand` -> `handleCommand`
- [x] 2.6 Test: verify `worker grant-skill marco grill` works, `worker grant-skill 2 1` still works, `worker grant-skill unknown grill` produces a clear error

## 3. Session Context

- [x] 3.1 Define `EntityType` enum (`WorkerCtx | SkillCtx | StationCtx | AbsenceTypeCtx`) and `EntityRef` (ID + display name) types; add `IORef (Map EntityType EntityRef)` to `AppState`
- [x] 3.2 Initialize the context `IORef` in `runRepl` and `runDemo` startup paths
- [x] 3.3 Add `Use String String`, `ContextView`, `ContextClear`, `ContextClearType String` command variants to `Commands.hs` and parse `use <type> <ref>`, `context view`, `context clear [type]`
- [x] 3.4 Implement handlers for `use`, `context view`, `context clear` in `handleCommand`
- [x] 3.5 Add dot-substitution in the resolution phase: before resolving entity refs, replace `"."` tokens with the context value for the expected entity type (requires knowing which argument position maps to which entity type)
- [x] 3.6 Test: verify `use worker marco` + `worker set-hours . 40` works; `context view` shows active contexts; `context clear` resets; `.` without context gives a clear error

## 4. Compact Schedule Display

- [x] 4.1 Add `ScheduleViewCompact String` command variant and parse `schedule view-compact <name>`
- [x] 4.2 Implement `displayScheduleCompact` in `CLI/Display.hs`: same row structure (day groups, station sub-rows), abbreviated hour headers (just number), truncated worker/station names, column widths tuned to fit 100 chars
- [x] 4.3 Implement unique-prefix name truncation: if two worker names share a prefix, extend both until distinguishable
- [x] 4.4 Wire the compact display command into `handleCommand`
- [x] 4.5 Test: verify compact output fits within 100 columns for a schedule with 5+ stations and 10+ hour columns

## 5. Checkpoint/Rollback

- [x] 5.1 Add `repoSavepoint`, `repoRelease`, `repoRollbackTo` functions to the `Repository` record in `Repo/Types.hs`
- [x] 5.2 Implement the three new repo functions in `Repo/SQLite.hs` using SQLite `SAVEPOINT`, `RELEASE SAVEPOINT`, and `ROLLBACK TO SAVEPOINT` statements
- [x] 5.3 Add `IORef [String]` (checkpoint stack) to `AppState`; initialize in REPL/demo startup
- [x] 5.4 Add command variants: `CheckpointCreate (Maybe String)`, `CheckpointCommit`, `CheckpointRollback (Maybe String)`, `CheckpointList`; parse `checkpoint create [name]`, `checkpoint commit`, `checkpoint rollback [name]`, `checkpoint list`
- [x] 5.5 Implement checkpoint handlers: create pushes onto stack + calls `repoSavepoint`; commit pops + calls `repoRelease`; rollback calls `repoRollbackTo` + trims stack; list displays stack
- [x] 5.6 Test: verify create/commit cycle, create/rollback cycle, nested checkpoints, rollback to named checkpoint, error on commit/rollback with no active checkpoint

## 6. Demo Auto-Export

- [x] 6.1 After `replayCommands` in `runDemo` (in `CLI/App.hs`), call `Export.gatherExport` and write the result to `demo-export.json` (or a path derived from the demo DB path)
- [x] 6.2 Print the export file path after writing
- [x] 6.3 Test: run demo mode and verify `demo-export.json` is created, contains expected entities, and is importable via `import` command

## 7. Integration and Cleanup

- [x] 7.1 Update `isMutating` to classify new commands (context/checkpoint commands as non-mutating for audit; use commands as non-mutating)
- [x] 7.2 Update the help registry to include all new commands (context, checkpoint, use, schedule view-compact)
- [x] 7.3 Verify the demo script still runs correctly with the new command parser
- [x] 7.4 End-to-end test: demo mode -> import export -> set context -> use names -> checkpoint -> rollback flow
