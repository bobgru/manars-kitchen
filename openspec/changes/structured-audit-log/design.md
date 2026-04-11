## Context

The audit log (`audit_log` table) currently stores `(id, timestamp, username, command)` where `command` is the raw CLI input string. Only mutating commands are logged, determined by `isMutating` in `CLI/App.hs` (whitelist of non-mutating patterns, everything else logged). The raw string is logged *before* parsing, preserving the original input including name-based references and dot-substitution tokens.

The `Command` ADT in `CLI/Commands.hs` has ~80 constructors with typed, validated fields. The `parseCommand` function pattern-matches on word lists. `isMutating` pattern-matches on the `Command` constructors.

## Goals

1. Make the audit log queryable by entity type, operation, and date range without reparsing command strings.
2. Introduce a `CommandMeta` type that serves as the canonical structured representation of a logged action.
3. Provide `classify` (command string to metadata) and `render` (metadata to command string) as a shared module usable by CLI dispatch, audit logging, terminal pane display, and future hint session rebase.
4. Keep the logging call sites unchanged — `repoLogCommand` signature and all 110+ command handlers remain untouched.

**Non-Goals:**

- Changing the `Command` ADT or `parseCommand`. The classifier is a separate, lighter-weight parser that extracts metadata without full command interpretation.
- Persisting the `ScheduleResult` or any scheduler output in the audit log.
- Supporting REST-originated audit entries yet. The `source` column is added but only `"cli"` is written in this change. REST logging comes with the HTTP layer.
- Migrating existing audit entries. Old rows will have structured columns set to NULL. The classifier can be applied retroactively if needed.

## Decisions

### CommandMeta lives in a new top-level module, not inside CLI/ or Repo/

The classifier will be imported by both `Repo/SQLite.hs` (for audit INSERT) and eventually by the hint rebase system and terminal pane renderer. Placing it under `CLI/` would create a dependency from `Repo/` to `CLI/`. Placing it under `Repo/` misrepresents its purpose. A top-level `CommandClassifier` module (or `Audit/CommandMeta.hs`) keeps it independent.

**Alternative considered:** Deriving metadata from the `Command` ADT directly (a function `Command -> CommandMeta`). Rejected because the logging happens before dispatch — we log the raw string, not the parsed command. The classifier must work on strings so it can also be used on historical audit entries and REST-originated metadata.

### classify reparses the command string rather than receiving structured data from handlers

The repo layer calls `classify` on the raw command string inside `sqlLogCommand`. This means the command is parsed twice (once by `parseCommand` for dispatch, once by `classify` for metadata). The duplication is acceptable because: (a) it requires zero changes to command handlers, (b) `classify` is much simpler than `parseCommand` — it only extracts entity/operation/IDs, not full command semantics, and (c) the same `classify` function works on historical audit entries for retroactive enrichment.

**Alternative considered:** Adding `CommandMeta` as a return value from `parseCommand` or `isMutating`. Rejected because it changes the interface used by every command handler and mixes concerns (dispatch vs. audit metadata).

### The command column becomes nullable; structured fields are the record of truth

For CLI/RPC-originated entries, both the raw command string and structured fields are populated. For future REST-originated entries, only structured fields are populated (command is NULL). Consumers that need a human-readable string use `render` on the structured fields — they never depend on the raw command column being present.

### Entity type uses a flat string, not an ADT

The `entity_type` column stores strings like `"worker"`, `"station"`, `"skill"`. Using a Haskell ADT would be cleaner but adds serialization overhead and rigidity. Strings match the command prefix naturally and are extensible without schema changes.

### Multi-entity commands use entity_id for the primary target and target_id for the secondary

Commands like `worker grant-skill 3 5` affect both a worker and a skill. Convention: `entity_type` is the command's noun prefix (`"worker"`), `entity_id` is the first ID argument (worker 3), `target_id` is the second (skill 5). This covers all existing commands — none touch more than two entity types.

## Risks / Trade-offs

**[Risk] classify falls out of sync with parseCommand when new commands are added.**
Mitigation: A test property — for every command string that `parseCommand` accepts and `isMutating` returns True, `classify` should produce a non-default `CommandMeta` (i.e., entity_type is not Nothing). This catches missing patterns at test time.

**[Risk] Reparsing adds overhead per logged command.**
Mitigation: Negligible. `classify` is simple string pattern matching on a short input. The SQLite INSERT dominates.

**[Risk] Old audit entries lack structured columns.**
Mitigation: Old rows have NULL structured fields. The `classify` function can be applied retroactively in a one-time migration script if needed. Not required for this change.
