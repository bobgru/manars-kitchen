## Why

The interactive CLI requires numeric IDs for all entity references, displays an overwhelming monolithic help screen, and lacks undo/rollback capabilities. These friction points slow down daily use—especially for operators who think in names ("marco", "grill") not IDs. As the command set has grown past 50 commands, discoverability has degraded and the schedule display doesn't fit on smaller terminals. These issues compound: new users struggle to learn the system, experienced users work slower than necessary, and there's no safety net for experimentation.

## What Changes

- **Two-level help**: `help` shows command group summaries; `help <group>` (e.g., `help schedule`) shows only commands in that group with detailed usage.
- **Name-based entity references**: Commands accept entity names or IDs interchangeably. `worker grant-skill marco grill` and `worker grant-skill 2 1` both work.
- **Session context**: `use worker marco` sets "marco" as the active worker context. Use `.` as a placeholder in any command argument to substitute the relevant context. `context view` shows current contexts; `context clear` resets them.
- **Compact schedule display**: A narrower table-format schedule view that fits within 100 columns, suitable for smaller terminals. The existing wide display remains available.
- **Checkpoint/rollback system**: `checkpoint create [name]` snapshots the current state. `checkpoint commit` accepts changes since the last checkpoint. `checkpoint rollback [name]` reverts to a checkpoint. Enables safe experimentation.
- **Demo auto-export**: The demo mode exports the full system JSON before exiting, so users can import it into an interactive session with ready-made data.

## Capabilities

### New Capabilities
- `two-level-help`: Grouped help display with per-group filtering via `help <group>`
- `name-based-entity-resolution`: Resolve entity arguments by name or ID, with disambiguation on conflicts
- `session-context`: Set, view, and clear per-entity-type session context; use `.` placeholder for substitution
- `compact-schedule-display`: Narrower schedule table view fitting within 100 columns
- `checkpoint-rollback`: Create, commit, and rollback named checkpoints for safe experimentation
- `demo-auto-export`: Automatically export full system JSON at end of demo mode

### Modified Capabilities

## Impact

- **CLI layer** (`cli/CLI/App.hs`, `cli/CLI/Commands.hs`, `cli/CLI/Display.hs`): Major changes to command parsing, dispatch, help, and display.
- **Command type** (`CLI/Commands.hs`): New command variants for context, checkpoint, and modified help.
- **Entity resolution**: New resolution layer between command parsing and handler dispatch, touching all commands that accept entity IDs.
- **State management** (`cli/CLI/App.hs`): `AppState` gains session context fields and checkpoint state.
- **Repository layer** (`src/Repo/`): Checkpoint may leverage SQLite savepoints or DB file copying.
- **Export module** (`src/Export/JSON.hs`): Minor change to wire export into demo exit path.
- **Demo mode** (`cli/CLI/App.hs`, `cli/Main.hs`): Export call added at demo completion.
