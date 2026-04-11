## 1. CommandMeta Type and Module

- [ ] 1.1 Create `src/Audit/CommandMeta.hs` module with `CommandMeta` record type
- [ ] 1.2 Define entity type strings as constants (worker, station, skill, shift, absence, user, config, schedule, draft, calendar, pin, what-if, checkpoint, import-export)
- [ ] 1.3 Add module to cabal file

## 2. classify Function

- [ ] 2.1 Implement `classify :: String -> CommandMeta` with pattern matching on word-split input
- [ ] 2.2 Cover all mutating command prefixes: schedule, station, skill, worker, shift, absence, user, config, draft, calendar, pin/unpin, import, what-if apply
- [ ] 2.3 Extract entity_id and target_id from numeric arguments where present
- [ ] 2.4 Extract date ranges from date-string arguments (YYYY-MM-DD format)
- [ ] 2.5 Set isMutation consistent with `isMutating` in CLI/App.hs
- [ ] 2.6 Handle variadic commands (set-prefs, set-shift-pref, override-prefs) by capturing extra args in params as JSON

## 3. render Function

- [ ] 3.1 Implement `render :: CommandMeta -> String` that produces a normalized command string
- [ ] 3.2 Handle all entity type / operation combinations that classify produces
- [ ] 3.3 Reconstruct variadic arguments from params JSON blob
- [ ] 3.4 Return a sensible fallback for incomplete metadata (e.g., just entity_type and operation)

## 4. Schema Migration

- [ ] 4.1 Add new columns to audit_log DDL in `Repo/Schema.hs`: entity_type, operation, entity_id, target_id, date_from, date_to, is_mutation, params, source
- [ ] 4.2 Make existing `command` column nullable in DDL
- [ ] 4.3 Add migration logic for existing databases (ALTER TABLE ADD COLUMN for each new field)

## 5. AuditEntry Type and Repo Interface

- [ ] 5.1 Define `AuditEntry` record type in `Repo/Types.hs`
- [ ] 5.2 Update `repoGetAuditLog` signature from `IO [(String, String, String)]` to `IO [AuditEntry]`
- [ ] 5.3 Update `sqlGetAuditLog` in `Repo/SQLite.hs` to SELECT all columns and construct AuditEntry values

## 6. Audit Logging with Classification

- [ ] 6.1 Import `Audit.CommandMeta` in `Repo/SQLite.hs`
- [ ] 6.2 Update `sqlLogCommand` to call `classify` on the command string before INSERT
- [ ] 6.3 Extend INSERT statement to populate all structured columns from CommandMeta
- [ ] 6.4 Ensure NULL structured fields on classify failure (no exceptions)

## 7. CLI Audit Display and Replay

- [ ] 7.1 Update `CmdAuditLog` handler in `CLI/App.hs` to consume `[AuditEntry]`
- [ ] 7.2 Display raw command when present, fall back to `render` when command is NULL
- [ ] 7.3 Update `CmdReplay` and `replayCommands` to consume `[AuditEntry]`
- [ ] 7.4 Replay from `aeCommand` when present, fall back to `render` when NULL

## 8. Testing

- [ ] 8.1 Unit tests for classify: one test per command group (schedule, station, skill, worker, shift, absence, user, config, draft, calendar, pin, what-if)
- [ ] 8.2 Unit tests for render: round-trip property for representative commands
- [ ] 8.3 Property test: `cmIsMutation (classify cmd) == isMutating (parseCommand cmd)` for all parseable commands
- [ ] 8.4 Property test: every mutating command produces a CommandMeta with non-Nothing cmEntityType
- [ ] 8.5 Integration test: log a command via repoLogCommand, read via repoGetAuditLog, verify structured fields populated
- [ ] 8.6 Test: legacy rows (NULL structured fields) are read correctly as AuditEntry with Nothing fields
