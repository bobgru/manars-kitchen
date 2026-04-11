## Why

The audit log currently stores raw command strings. This works for CLI replay but does not support two upcoming needs: (1) hint session rebase, which must classify audit entries by entity type, affected IDs, and date range to determine relevance; and (2) the web interface, where mutations arrive via REST endpoints that have no natural command string. The audit log needs a structured canonical form that all interfaces can write and all consumers can query, with command strings becoming a rendering convenience rather than the source of truth.

See `openspec/web-interface-roadmap.md` for full context (this is Change 1).

## What Changes

- **New `CommandMeta` type** captures the structured content of any mutation: entity type, operation name, entity ID, optional target ID, optional date range, whether it is a mutation, and an optional JSON blob for operation-specific parameters.
- **New `CommandClassifier` module** with two functions: `classify :: String -> CommandMeta` (parses a raw command string into metadata) and `render :: CommandMeta -> String` (generates a human-readable command string from metadata). The property `render . classify` is approximately identity (modulo whitespace and alias normalization).
- **`audit_log` schema extended** with columns: `entity_type`, `operation`, `entity_id`, `target_id`, `date_from`, `date_to`, `is_mutation`, `params`, and `source` (cli/rpc/rest). The existing `command` column becomes nullable (present for CLI/RPC, NULL for REST).
- **`repoLogCommand` unchanged at the call sites.** The repo layer internally calls `classify` on the command string to extract metadata before INSERT. No changes to the 110+ command handlers.
- **`repoGetAuditLog` returns structured records** instead of `(String, String, String)` triples. A new `AuditEntry` type carries all fields.

## Capabilities

### New Capabilities
- `command-classifier`: Shared module for bidirectional translation between raw command strings and structured command metadata. Supports CLI dispatch, audit logging, terminal pane display, and hint session rebase.

### Modified Capabilities
- `audit-log`: Extended from flat text records to structured metadata with source tracking. Read interface returns typed `AuditEntry` values. Write interface unchanged for CLI callers.

## Impact

- **New module**: `CommandClassifier.hs` (or `Domain/CommandMeta.hs`) with `CommandMeta` type, `classify`, and `render`.
- **`Repo/Schema.hs`**: Extended `audit_log` DDL with new columns, migration for existing data.
- **`Repo/Types.hs`**: New `AuditEntry` type replaces `(String, String, String)` in `repoGetAuditLog` signature.
- **`Repo/SQLite.hs`**: `sqlLogCommand` calls `classify` before INSERT. `sqlGetAuditLog` returns `[AuditEntry]`.
- **`CLI/App.hs`**: Audit display commands (`audit`, `replay`) updated to consume `AuditEntry`. Replay can use structured data instead of reparsing.
- **No changes** to command handlers, service layer, or domain logic.
