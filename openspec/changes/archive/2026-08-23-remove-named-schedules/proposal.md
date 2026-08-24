## Why

Named schedules are the first-generation scheduling surface: a `schedules` table
keyed by an operator-chosen name, an `assignments` table hanging off it, and a
`schedule create` / `view` / `assign` / `unassign` / `calendar commit <name>`
command family. Drafts replaced them (ADR 0001) and the calendar replaced their
output. Everything a named schedule can do, a draft does with real pay-period
bounds, station closures, calendar hours, validation and history.

Keeping both means every new feature has to be written twice or explained twice,
and the `/drafts` page cannot be built without deciding which of the two surfaces
it targets. That decision is already made and recorded in `docs/STATUS.md`: the
page targets drafts and the calendar. This change deletes the surface it does not
target, so nothing downstream has to keep pretending named schedules exist.

## What Changes

**Deleted outright**

- `src/Service/Schedule.hs` and its cabal entry.
- `Repository` fields `repoSaveSchedule`, `repoLoadSchedule`, `repoListSchedules`,
  `repoDeleteSchedule`, and the four `sql*` implementations behind them.
- The `CREATE TABLE` statements for `schedules` and `assignments` — **statements
  only, no `DROP TABLE`**. Existing databases keep the rows; the code stops
  reading them. A fresh database simply never grows the tables.
- CLI: `schedule list` / `view` / `view-compact` / `view-by-worker` /
  `view-by-station` / `hours` / `diagnose` / `create` / `delete` / `clear`,
  `assign`, `unassign`, `export <name> <file>`, and the whole `schedule` help
  group. `export <file>` is a different command and stays.
- `calendar commit <name> <start> <end> [note]`, whose only source of assignments
  was a named schedule. `draft commit` is the surviving way to write the calendar.
- REST `GET /api/schedules`, `GET /api/schedules/:name`,
  `DELETE /api/schedules/:name` and their three RPC twins.
- `Audit.CommandMeta.classifySchedule`, `classifyAssign`, `classifyUnassign`, the
  `isMutating` arms for the removed constructors, and the `assign` / `unassign`
  entries in `CLI.Resolve.commandEntityMap`.

**Changed rather than deleted** — four dependencies that a naive removal would
break:

1. **Export/import.** `ExportData` loses its `expSchedules` field and the
   `schedules` JSON key; `gatherExport` loses its `Maybe Text` schedule-name
   parameter. `export.json` and `demo-export.json` are regenerated. `FromJSON`
   already read the key with `.:?`, so an older export file still parses — its
   schedules are simply dropped, which is the only thing left to do with them.
2. **Worker safe-delete.** `WorkerReferences` loses `wrSchedule`, and the
   named-schedule scan in `checkWorkerReferences` goes with it. `wrCalendar`,
   `wrDraft` and `wrPinned` already cover every place a worker can still be
   referenced by an assignment.
3. **`sqlWipeAll` and `sqlCascadeWorkerSchedule`.** Both issue
   `DELETE FROM assignments` (and `sqlWipeAll` also `DELETE FROM schedules`).
   Once the `CREATE TABLE` statements are gone these fail with *no such table* on
   any fresh database, so the statements have to be removed in the same commit,
   not left behind.
4. **The demo.** `demo/restaurant-setup.txt` opens by building week 1 as a named
   schedule and committing it with `calendar commit week1`. That section is
   rewritten onto a draft. Committing a draft consumes an id, so every later
   draft id in the file shifts by one.

**Spec deltas** — `assign-name-args` and `compact-schedule-display` are removed
outright; `calendar-cli`, `command-classifier`, `demo-auto-export`,
`endpoint-authorization`, `name-based-entity-resolution`, `readme-cli-features`,
`two-level-help`, `worker-deactivate` and `worker-delete` lose their
named-schedule clauses.

## Impact

- Affected specs: `assign-name-args` (removed), `compact-schedule-display`
  (removed), `calendar-cli`, `command-classifier`, `demo-auto-export`,
  `endpoint-authorization`, `name-based-entity-resolution`,
  `readme-cli-features`, `two-level-help`, `worker-deactivate`, `worker-delete`.
- Affected code: `src/Service/Schedule.hs` (deleted), `src/Repo/Types.hs`,
  `src/Repo/SQLite.hs`, `src/Repo/Schema.hs`, `src/CLI/Commands.hs`,
  `src/CLI/App.hs`, `src/CLI/Resolve.hs`, `src/Audit/CommandMeta.hs`,
  `src/Export/JSON.hs`, `src/Service/Worker.hs`, `src/CLI/Display.hs`,
  `cli/CLI/RpcClient.hs`, `server/Server/Api.hs`, `server/Server/Handlers.hs`,
  `server/Server/Rpc.hs`, `web/src/components/Sidebar.tsx`,
  `demo/restaurant-setup.txt`, `export.json`, `demo-export.json`,
  `test/ApiSpec.hs`, `test/AuditSpec.hs`, `test/EventStreamSpec.hs`.
- **Data is not destroyed.** No `DROP TABLE`, no `DELETE`. An operator who wants
  the old rows can still read them with `sqlite3`.
- **Breaking for any script that calls the removed commands or endpoints.** There
  is no deprecation window; the CLI is the only client and it ships in this repo.
