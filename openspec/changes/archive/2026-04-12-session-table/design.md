## Context

CLI session state currently lives in four IORefs inside `AppState`: `asContext` (entity resolution context), `asCheckpoints` (savepoint names), `asUnfreezes` (temporarily unfrozen date ranges), and `asHintSession` (what-if exploration). All state is lost on process exit.

The web interface roadmap requires server-side sessions so that state can persist across HTTP requests and survive crashes. This change introduces only the session table and lifecycle — no state is migrated yet. Subsequent changes will move each IORef field into the session record one at a time.

The startup flow is: `mkSQLiteRepo` -> `ensureAdminExists` -> `loginLoop` -> `mkAppState` -> `runRepl`. The session lifecycle hooks into this at `mkAppState` (create session) and `runRepl` (touch on each command, close on quit).

## Goals

1. Introduce a `sessions` table that tracks active sessions per user.
2. Wire create/touch/close into the CLI startup and REPL loop.
3. Offer session resumption at login when an active session exists.
4. Keep session state migration out of scope — IORefs remain, session record is just a lifecycle shell.

**Non-Goals:**

- Migrating any IORef state into the session record. That is a separate change per state type.
- HTTP session management (cookies, tokens). That comes with the REST API.
- Session timeout or garbage collection. Sessions are closed explicitly on quit. Stale sessions (from crashes) remain `is_active = 1` until the user resumes or starts fresh.

## Decisions

### Session identified by auto-incremented integer, wrapped in a newtype

A `SessionId` newtype wrapping `Int` follows the existing pattern (`WorkerId`, `UserId`, `StationId`). Auto-increment avoids UUID dependencies and matches the SQLite idiom used throughout.

**Alternative considered:** UUIDs for globally unique session identifiers. Rejected as premature — no distributed system or external references exist yet. Easy to change later if needed.

### Resume-or-new prompt at login, not automatic resume

When a user logs in and has an active session, the CLI asks whether to resume it or start fresh. Starting fresh closes the old session and creates a new one. This makes the lifecycle explicit and avoids surprising behavior.

For now, since no state is persisted in the session, the choice has no functional difference — but the plumbing is in place so that when state migration happens, resuming picks up where the user left off.

**Alternative considered:** Always auto-resume if an active session exists. Rejected because stale sessions from crashes would silently resume with potentially stale state once state migration happens.

### Touch updates last_active_at on every mutating command, not every command

Updating on every keystroke would add noise. Updating only when a mutating command runs (already gated by `isMutating`) is sufficient for staleness detection and adds zero overhead to read-only browsing.

### Session close on Quit is best-effort

The `Quit` handler calls `repoCloseSession`. If the process is killed (Ctrl-C, crash), the session stays active in the database. This is acceptable — the resume-or-new prompt handles it on next login. No background cleanup thread needed.

## Risks / Trade-offs

**[Risk] Stale sessions accumulate from crashes.** Mitigation: The resume-or-new prompt handles this. A future cleanup pass can close sessions older than N days if needed — not required now.

**[Risk] Adding SessionId to AppState is a breaking change for test code that constructs AppState.** Mitigation: `mkAppState` is the only constructor used. Tests that call `mkAppState` will pass a repo that has session support. No test constructs `AppState` by hand.
