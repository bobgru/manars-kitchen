## Context

Hint sessions are currently ephemeral `IORef (Maybe Session)` values in the CLI's `AppState`. The `Session` record holds the original `SchedulerContext`, a `[Hint]` list, and the latest `ScheduleResult`. On exit, crash, or any mutating command, the entire session is lost.

The structured audit log (change 1) records every command with classified metadata (`CommandMeta`), and server-side sessions (change 2) give each CLI invocation a persistent `SessionId`. This change bridges the two: hint lists persist in SQLite keyed by session + draft, and the audit log provides a changelog for detecting what happened while the hint session was dormant.

## Goals / Non-Goals

**Goals:**
- Hint sessions survive CLI exit and crash — users can resume where they left off.
- When the underlying data changes between hint session interactions, the system detects and classifies those changes so hints can be reconciled rather than silently invalidated.
- Draft mutations no longer silently destroy the hint session; instead the session is marked stale and the user can rebase.
- `what-if apply` keeps the audit checkpoint in sync so applying a hint doesn't immediately trigger a stale-session warning.

**Non-Goals:**
- Multi-user collaborative hint sessions (one session per server-side session).
- Persisting the `SchedulerContext` or `ScheduleResult` — these are rebuilt on resume from current database state. Only the `[Hint]` list and checkpoint are stored.
- Automatic background rebase — rebase is always user-initiated via `what-if rebase` or prompted on resume.
- REST API integration — this change is CLI-only; the REST layer will consume the same service functions later.

## Decisions

### 1. Storage: JSON blob in a `hint_sessions` table

**Decision:** Store hint sessions as a single row per (session_id, draft_id) pair, with the hint list serialized as a JSON text column and an integer checkpoint referencing the audit log.

```sql
CREATE TABLE IF NOT EXISTS hint_sessions (
  session_id  INTEGER NOT NULL,
  draft_id    INTEGER NOT NULL,
  hints_json  TEXT NOT NULL,         -- JSON-encoded [Hint]
  checkpoint  INTEGER NOT NULL,      -- audit_log.id of last-seen entry
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (session_id, draft_id)
);
```

**Why JSON over normalized tables:** Hints are a heterogeneous sum type with 6 variants and varying payloads. A normalized schema would require a discriminator column plus nullable columns for each variant's fields. JSON is simpler, the hint list is small (typically < 20 items), and we never need to query individual hints — they're always loaded and saved as a batch.

**Alternative considered:** Separate `hint_session` + `hint_entries` tables with a `hint_type` discriminator. Rejected because it adds schema complexity for no query benefit — we always load the full list.

### 2. Checkpoint: audit log entry ID

**Decision:** The checkpoint is the `audit_log.id` of the most recent entry at the time the hint session was last saved. On resume, we query `SELECT * FROM audit_log WHERE id > checkpoint AND is_mutation = 1` to find what changed.

**Why audit log ID over timestamp:** IDs are monotonically increasing integers with no timezone ambiguity. The audit log already has an autoincrement primary key.

### 3. Change classification for rebase

**Decision:** When resuming a stale hint session, each new audit entry is classified into one of four categories based on its `CommandMeta`:

| Category | Meaning | Action |
|----------|---------|--------|
| **Irrelevant** | Doesn't affect scheduler context (e.g., `user create`, `export`, `config show`) | Skip silently |
| **Compatible** | Affects context but doesn't conflict with any active hint (e.g., adding a new station when no hints reference it) | Auto-integrate |
| **Conflicting** | Directly contradicts an active hint (e.g., `worker revoke-skill 3 2` when there's a `GrantSkill 3 2` hint) | Prompt user |
| **Structural** | Changes the draft itself (e.g., `draft commit`, `draft discard`, `draft create`) | Session invalid — must discard |

Classification uses `CommandMeta` fields (entity_type, operation, entity_id, target_id) to determine overlap with each hint's affected entities. The logic lives in a new `Service.HintRebase` module.

**Conflict detection rules:**
- `GrantSkill w s` conflicts with `worker revoke-skill w s`
- `WaiveOvertime w` conflicts with `worker set-overtime w off`
- `CloseStation st slot` conflicts with mutations to that station's configuration
- `PinAssignment w st slot` conflicts with mutations to worker `w` or station `st`
- `AddWorker` conflicts only with structural changes (it introduces a synthetic worker)
- `OverridePreference w _` conflicts with `worker set-prefs w ...`

**Alternative considered:** Re-running all hints against the new context and checking if the schedule diff is "surprising." Rejected because it's slow (requires full optimization) and doesn't give the user actionable information about *what* changed.

### 4. Auto-save on every hint operation

**Decision:** Every `what-if` command that modifies the hint list (add, revert, revert-all, apply) auto-saves the session to SQLite. There is no explicit `what-if save` command — persistence is transparent.

**Why auto-save over explicit save:** The whole point of persistence is crash recovery and cross-session continuity. Requiring an explicit save defeats the purpose — users who forget to save still lose work.

**Alternative considered:** Explicit `what-if save` / `what-if resume` commands. Rejected in favor of auto-save. A `what-if resume` is also unnecessary — on draft open, if a persisted hint session exists, the system offers to resume it automatically.

### 5. Resume flow on draft open

**Decision:** When the user opens a draft (or starts the CLI with an active draft), the system checks for a persisted hint session for the current (session_id, draft_id). If found:

1. Load the hint list and checkpoint from `hint_sessions`.
2. Query audit log for entries since checkpoint.
3. If no new mutations → resume directly, rebuild `Session` from current context + loaded hints.
4. If new mutations exist → classify each, then:
   - All irrelevant/compatible → auto-rebase and resume, show summary of integrated changes.
   - Any conflicting → show conflicts and prompt: rebase (drop conflicting hints), keep all (force), or discard session.
   - Any structural → session is invalid, inform user, delete persisted session.

### 6. Hint JSON serialization

**Decision:** Add `ToJSON`/`FromJSON` instances for `Hint` using Aeson. The JSON format uses a tagged encoding:

```json
{"tag": "GrantSkill", "workerId": 3, "skillId": 2}
{"tag": "CloseStation", "stationId": 1, "day": "2026-04-06", "hour": 9, "duration": 3600}
```

The `Slot` type serializes as `{day, hour, duration}` rather than nesting a `TimeOfDay`, for readability and forward compatibility.

### 7. Stale marking instead of session destruction

**Decision:** When a mutating command is executed while a hint session is active, the current behavior (destroy the session) changes to: bump the checkpoint to the current audit entry and mark the session as needing rebase. The next hint operation triggers the rebase flow.

**Why:** This preserves the user's exploration. The old behavior was acceptable when sessions were ephemeral (losing in-memory state is expected on mutation). With persistence, silently deleting stored work would be surprising.

## Risks / Trade-offs

**[Risk] Hint JSON format migration** → The JSON schema is effectively an API. If `Hint` type variants change in the future, old persisted sessions may fail to deserialize.
→ *Mitigation:* On deserialization failure, log a warning and offer to discard the session. The `tag` field makes the format extensible.

**[Risk] Large audit gaps** → If a user resumes a session after hundreds of mutations, rebase classification could be slow or produce many conflicts.
→ *Mitigation:* If more than N (e.g., 50) mutations since checkpoint, skip classification and prompt "significant changes detected — discard or force resume?"

**[Risk] Rebase classification false negatives** → A mutation might affect scheduling context in a way that doesn't directly reference the same entity IDs as a hint (e.g., changing skill implications).
→ *Mitigation:* Classify `skill implication` changes as potentially conflicting with any `GrantSkill` hint. Accept that edge cases exist — the rebuilt schedule diff will surface surprises.

**[Trade-off] Auto-save adds a write on every hint operation** → Acceptable. Hint operations already run the optimizer, which takes orders of magnitude longer than a single SQLite write.
