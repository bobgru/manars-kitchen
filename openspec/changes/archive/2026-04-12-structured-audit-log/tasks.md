## 1. CommandMeta Type and Module

- [x] 1.1 Create `src/Audit/CommandMeta.hs` module with `CommandMeta` record type
- [x] 1.2 Define entity type strings as constants (worker, station, skill, shift, absence, user, config, schedule, draft, calendar, pin, what-if, checkpoint, import-export)
- [x] 1.3 Add module to cabal file

## 2. classify Function

- [x] 2.1 Implement `classify :: String -> CommandMeta` with pattern matching on word-split input
- [x] 2.2 Cover all mutating command prefixes: schedule, station, skill, worker, shift, absence, user, config, draft, calendar, pin/unpin, import, what-if apply
- [x] 2.3 Extract entity_id and target_id from numeric arguments where present
- [x] 2.4 Extract date ranges from date-string arguments (YYYY-MM-DD format)
- [x] 2.5 Set isMutation consistent with `isMutating` in CLI/App.hs
- [x] 2.6 Handle variadic commands (set-prefs, set-shift-pref, override-prefs) by capturing extra args in params as JSON

## 3. render Function

- [x] 3.1 Implement `render :: CommandMeta -> String` that produces a normalized command string
- [x] 3.2 Handle all entity type / operation combinations that classify produces
- [x] 3.3 Reconstruct variadic arguments from params JSON blob
- [x] 3.4 Return a sensible fallback for incomplete metadata (e.g., just entity_type and operation)

## 4. Schema Migration

- [x] 4.1 Add new columns to audit_log DDL in `Repo/Schema.hs`: entity_type, operation, entity_id, target_id, date_from, date_to, is_mutation, params, source
- [x] 4.2 Make existing `command` column nullable in DDL
- [x] 4.3 Add migration logic for existing databases (ALTER TABLE ADD COLUMN for each new field)

## 5. AuditEntry Type and Repo Interface

- [x] 5.1 Define `AuditEntry` record type in `Repo/Types.hs`
- [x] 5.2 Update `repoGetAuditLog` signature from `IO [(String, String, String)]` to `IO [AuditEntry]`
- [x] 5.3 Update `sqlGetAuditLog` in `Repo/SQLite.hs` to SELECT all columns and construct AuditEntry values

## 6. Audit Logging with Classification

- [x] 6.1 Import `Audit.CommandMeta` in `Repo/SQLite.hs`
- [x] 6.2 Update `sqlLogCommand` to call `classify` on the command string before INSERT
- [x] 6.3 Extend INSERT statement to populate all structured columns from CommandMeta
- [x] 6.4 Ensure NULL structured fields on classify failure (no exceptions)

## 7. CLI Audit Display and Replay

- [x] 7.1 Update `CmdAuditLog` handler in `CLI/App.hs` to consume `[AuditEntry]`
- [x] 7.2 Display raw command when present, fall back to `render` when command is NULL
- [x] 7.3 Update `CmdReplay` and `replayCommands` to consume `[AuditEntry]`
- [x] 7.4 Replay from `aeCommand` when present, fall back to `render` when NULL

## 8. Testing

- [x] 8.1 Unit tests for classify: one test per command group (schedule, station, skill, worker, shift, absence, user, config, draft, calendar, pin, what-if)
- [x] 8.2 Unit tests for render: round-trip property for representative commands
- [x] 8.3 Property test: `cmIsMutation (classify cmd) == isMutating (parseCommand cmd)` for all parseable commands
- [x] 8.4 Property test: every mutating command produces a CommandMeta with non-Nothing cmEntityType
- [x] 8.5 Integration test: log a command via repoLogCommand, read via repoGetAuditLog, verify structured fields populated
- [x] 8.6 Test: legacy rows (NULL structured fields) are read correctly as AuditEntry with Nothing fields
