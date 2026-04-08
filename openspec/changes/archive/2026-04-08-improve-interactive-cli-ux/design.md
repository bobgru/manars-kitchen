## Context

Manars Kitchen is a Haskell CLI application for restaurant workforce scheduling. The interactive REPL (`cli/CLI/App.hs`) parses text commands via `parseCommand` (in `CLI/Commands.hs`), dispatches them through a large `handleCommand` case statement, and renders output via `CLI/Display.hs`. State is persisted to SQLite through a record-of-functions `Repository` interface (`src/Repo/Types.hs`).

The CLI currently has 50+ commands, all referencing entities by numeric ID. The help system is a single monolithic `printHelp` function. `AppState` holds only the repository handle and current user — no session-level context. There is no undo/rollback mechanism.

## Goals / Non-Goals

**Goals:**
- Make the CLI more usable for operators who think in names, not IDs
- Reduce cognitive load when exploring commands
- Enable safe experimentation with rollback
- Support narrower terminals (100 columns) for schedule viewing
- Provide a smoother onboarding path via demo auto-export

**Non-Goals:**
- Tab completion or readline integration (future enhancement)
- Multi-user concurrent session contexts (this is a single-user REPL)
- Persistent contexts across sessions (contexts are session-only)
- Changing the Repository interface for name-based lookups (resolution happens in the CLI layer)

## Decisions

### 1. Two-level help via command group registry

**Decision:** Organize commands into named groups (schedule, worker, skill, station, shift, absence, config, pin, import/export, audit). `help` prints group names with one-line descriptions. `help <group>` prints only commands in that group.

**Rationale:** A flat list of 80+ lines is overwhelming. Group-based filtering is the simplest approach that scales. A data-driven registry (list of `(group, command, description)` tuples) replaces the current `printHelp` function, making it easy to add commands without updating help formatting logic.

**Alternative considered:** Pager-based help (piping through `less`). Rejected because it adds an external dependency and doesn't help with discoverability — users still need to scan the full list.

### 2. Name-based entity resolution in the parser layer

**Decision:** Add a resolution phase between raw `words` parsing and `Command` construction. When a token is expected to be an entity ID but doesn't parse as a number, look it up by name via the repository. The `parseCommand` function becomes `resolveCommand :: Repository -> String -> IO Command`, or alternatively a two-phase approach: `parseCommand` returns a `RawCommand` with `Either String Int` for entity references, then `resolveCommand` resolves names to IDs.

**Rationale:** The two-phase approach keeps parsing pure and testable. Resolution is the only step that needs IO (to look up names). This minimizes changes to `handleCommand` — it still receives `Command` with resolved `Int` IDs.

**Alternative considered:** Making `handleCommand` accept names and resolve inline. Rejected because it would require changing every handler and mixing resolution logic with business logic.

**Entity types needing resolution:** WorkerId (by username), SkillId (by skill name), StationId (by station name). AbsenceTypeId resolution is also useful. ScheduleId is already a string name, not a numeric ID.

**Disambiguation:** If a name matches multiple entities (unlikely in practice since names are unique per type), print an error listing matches. If the token is a valid integer, always prefer the ID interpretation.

### 3. Session context stored in AppState with dot-placeholder substitution

**Decision:** Extend `AppState` with a `Map EntityType EntityRef` where `EntityType` is one of `WorkerCtx | SkillCtx | StationCtx | AbsenceTypeCtx` and `EntityRef` stores both the resolved ID and the display name. New commands: `use <entity-type> <name-or-id>`, `context view`, `context clear`, `context clear <entity-type>`.

Dot-substitution happens in the resolution phase: before resolving entity references, replace any `"."` token with the current context value for the expected entity type. If no context is set for that type, print an error.

**Rationale:** Storing context in `AppState` is natural since the REPL already threads `AppState` through the loop. Dot-substitution at the resolution layer means `handleCommand` doesn't need any changes to support it.

**Alternative considered:** Storing context per-entity rather than per-type (e.g., "use marco" without specifying "worker"). Rejected because it's ambiguous — "marco" could be a worker, station, or skill name.

### 4. Compact schedule display via abbreviated table

**Decision:** Add `displayScheduleCompact` that fits within 100 columns. Strategy: truncate worker names to 3-4 characters, use narrower column widths (4-5 chars), abbreviate hour headers (just the number, no ":00"), and show station names as 3-char abbreviations. The existing wide display remains as the default; a `schedule view-compact <name>` command invokes the compact version.

**Rationale:** The current table uses dynamic column widths that can grow to 8+ characters per hour column. With 11 hour columns and station labels, this easily exceeds 100 chars. Truncation is the simplest approach that preserves the table structure.

**Alternative considered:** Vertical/rotated layout (hours as rows, stations as columns). Rejected because it breaks the mental model of the existing wide display — users should see the same structure, just narrower.

### 5. Checkpoint/rollback via SQLite SAVEPOINT

**Decision:** Implement checkpoints using SQLite's `SAVEPOINT` / `RELEASE` / `ROLLBACK TO` mechanism. Store a stack of checkpoint names in `AppState`. `checkpoint create [name]` issues `SAVEPOINT <name>` (auto-generating a name if omitted). `checkpoint commit` issues `RELEASE SAVEPOINT` for the top of the stack. `checkpoint rollback [name]` issues `ROLLBACK TO SAVEPOINT <name>`.

**Rationale:** SQLite savepoints are nested, lightweight, and require no file copying or schema changes. They map directly to the user's mental model of "save point, try stuff, undo if needed." The Repository interface needs one addition: a `repoRawSQL :: String -> IO ()` or more targeted `repoSavepoint / repoRelease / repoRollback` functions.

**Alternative considered:** File-level DB copying (copy the .db file as a checkpoint). Simpler conceptually but expensive for large databases, doesn't support nesting, and requires filesystem operations outside the Repository abstraction.

**Constraint:** Savepoints only work within a single SQLite connection. Since the REPL uses one connection for its entire lifetime, this is fine.

### 6. Demo auto-export wired into runDemo exit path

**Decision:** After `replayCommands` completes in `runDemo`, call `Export.gatherExport` and write to a well-known path (e.g., `demo-export.json` in the current directory, or alongside the demo DB). Print the path so the user knows where to find it.

**Rationale:** Minimal change — one function call at the end of `runDemo`. The export machinery already exists and handles all entity types.

## Risks / Trade-offs

**[Name collision across entity types]** A worker named "grill" and a skill named "grill" are distinct. Since resolution is typed (we know which argument position expects which entity type), this is not a problem in practice. -> Mitigation: Resolution is always type-directed.

**[SQLite savepoint limitations]** Savepoints don't survive process crashes or disconnections. If the CLI is killed mid-session, uncommitted checkpoints are lost (rolled back). -> Mitigation: Document this behavior. It matches user expectations — a crash is equivalent to rollback.

**[Compact display readability]** Aggressive truncation may make names ambiguous (e.g., "mar" for both "marco" and "maria"). -> Mitigation: Use unique-prefix truncation where possible; if two names share a prefix, extend both until unique.

**[AppState threading]** Currently `runRepl` and `handleCommand` return `IO ()` and restart the loop. Adding mutable context to `AppState` requires either an `IORef` for the context map or changing the loop to thread a modified `AppState`. -> Mitigation: Use an `IORef (Map EntityType EntityRef)` inside `AppState` for context and an `IORef [String]` for the checkpoint stack. This avoids changing the `handleCommand` signature.
