## Why

CLI session state (entity context, checkpoints, unfreezes, hint sessions) lives in IORefs and is lost on process exit. The web interface roadmap requires server-side sessions so that state persists across requests, survives crashes, and supports multiple concurrent clients. This change introduces the session table and lifecycle (create/resume/close) without migrating any state into it yet — establishing the foundation that subsequent changes will build on.

See `openspec/web-interface-roadmap.md` for full context (this is Change 2, step 1 of 4).

## What Changes

- **New `sessions` table** with columns: `id`, `user_id`, `created_at`, `last_active_at`, `is_active`. Tracks which user owns the session and whether it is still open.
- **New `SessionId` type** in `Repo/Types.hs` as a newtype wrapper around `Int`.
- **New repo functions**: `repoCreateSession`, `repoResumeSession`, `repoCloseSession`, `repoTouchSession` (update `last_active_at`), `repoGetActiveSession`.
- **AppState gains a `SessionId` field.** `mkAppState` creates a session on startup. The REPL touches the session on each command. `Quit` closes the session.
- **Session resumption on login.** If a user has an existing active session, they are offered the choice to resume it or start fresh. For now, since no state is persisted in the session yet, resuming vs. starting fresh is functionally identical — but the lifecycle is wired up.

## Capabilities

### New Capabilities
- `session-lifecycle`: Database-backed session records with create/resume/close lifecycle, wired into the CLI startup and REPL loop.

### Modified Capabilities

## Impact

- **`Repo/Schema.hs`**: New `sessions` table DDL.
- **`Repo/Types.hs`**: `SessionId` newtype, new repo function signatures, `AuditEntry` gains optional `session_id`.
- **`Repo/SQLite.hs`**: Implementations of session repo functions.
- **`CLI/App.hs`**: `AppState` gains `asSessionId`. `mkAppState` creates a session. REPL loop touches session. Quit closes session.
- **`cli/Main.hs`**: Login flow offers session resumption when an active session exists.
