## Why

Hint sessions are currently ephemeral — stored in a CLI `IORef` and lost on exit, crash, or draft mutation. This forces users to rebuild their what-if exploration from scratch each time. Persisting hints to SQLite and adding a rebase mechanism lets sessions survive across CLI invocations, and when the underlying data changes (e.g., another admin commits schedule edits), the user can reconcile rather than start over. This is also a prerequisite for the REST API layer, where hint state must live server-side.

## What Changes

- Hint sessions are stored in SQLite as a JSON blob of `[Hint]` plus an audit-log checkpoint (the last-seen audit entry ID at session creation or last rebase).
- Sessions are tied to both a server-side session (from change 2) and the active draft.
- On session resume, the system replays audit entries since the checkpoint, classifies each as irrelevant/compatible/conflicting/structural using `CommandClassifier`, and either auto-integrates or presents a rebase prompt.
- New CLI commands: `what-if save` (persist without closing), `what-if resume` (reload persisted session), `what-if rebase` (reconcile with data changes).
- Draft mutation no longer silently destroys hints — instead it marks the session as needing rebase.
- `what-if apply` updates the audit checkpoint after persisting the real mutation.

## Capabilities

### New Capabilities
- `hint-persistence`: Storage, save, and resume of hint sessions in SQLite. Covers the hint_sessions table, repo functions, and CLI save/resume commands.
- `hint-rebase`: Audit-log-driven conflict detection and reconciliation when resuming a stale hint session. Covers change classification, auto-integration, conflict prompts, and the `what-if rebase` command.

### Modified Capabilities
- `hint-cli`: Existing what-if commands gain persistence awareness — session auto-saved on each hint operation, `what-if apply` updates the checkpoint, draft mutation marks the session stale instead of destroying it.

## Impact

- **Domain**: New `HintSessionRecord` type; hint session operations gain persistence semantics.
- **Repo**: New `hint_sessions` table and repo functions (`repoSaveHintSession`, `repoLoadHintSession`, `repoDeleteHintSession`).
- **Service**: Rebase logic reads audit log entries since checkpoint and classifies via `CommandClassifier`.
- **CLI**: New commands (`save`, `resume`, `rebase`); modified draft-mutation handler; session resume flow on startup checks for persisted hint session.
- **Audit**: Read path only — queries entries after a given ID. No schema changes.
- **Sessions**: Read path only — hint sessions reference the server-side session ID. No schema changes.
