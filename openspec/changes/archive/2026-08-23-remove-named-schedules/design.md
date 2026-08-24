## Context

Two surfaces write assignments: named schedules (`schedules` + `assignments`,
reached through `Service.Schedule`) and drafts (`drafts` + `draft_assignments`,
reached through `Service.Draft`). Only the second one feeds the calendar in a way
anyone still uses, and only the second one is validated, rebased, freeze-checked
and exposed over REST. ADR 0001 already decided drafts supersede named schedules;
this change is the follow-through.

The prerequisite change `2026-08-23-draft-generate-optimizes` moved the optimizer
onto `draft generate` precisely so that this removal has no live dependency on it.
Nothing here touches `Service.Optimize` or `Domain.Optimizer`.

## Decisions

### The tables are orphaned, not dropped

The `CREATE TABLE IF NOT EXISTS` statements for `schedules` and `assignments` are
deleted; no `DROP TABLE` is added. An existing database keeps both tables and
every row in them, unreadable by this build but readable by `sqlite3`. A fresh
database never creates them.

The alternative — a migration that drops them — was rejected because there is no
migration framework here (`Repo.Schema` is an idempotent list of
`CREATE TABLE IF NOT EXISTS`), so a drop would have to run unconditionally on
every open, and a bug in it destroys data that a user may not have finished
copying out. Leaving dead tables costs nothing.

The consequence that a naive removal misses: `sqlWipeAll` and
`sqlCascadeWorkerSchedule` issue `DELETE FROM assignments`, and `sqlWipeAll` also
`DELETE FROM schedules`. Against a fresh database with the `CREATE TABLE`
statements gone, those raise *no such table* — so `demo` and `worker force-delete`
would break on exactly the machines where the tables were never created. The
statements are removed in the same commit.

### `calendar commit <name>` goes away rather than being repointed

`calendar commit` took a named schedule and wrote it to the calendar. The obvious
salvage is `calendar commit <draft-id>`, but that is `draft commit` — same
service call (`Service.Calendar.commitToCalendar`), plus the draft cleanup and
freeze handling that `calendar commit` never had. Two spellings of one operation
is what this change exists to remove.

`Service.Calendar.commitToCalendar` itself stays; `commitDraft` is its caller.

### `wrSchedule` is removed from `WorkerReferences`, not zeroed

Leaving the field pinned at `0` would keep `worker delete`'s refusal message
printing a `schedule assignments: 0` line forever. The three surviving assignment
counters — `wrPinned`, `wrCalendar`, `wrDraft` — cover every table a worker can
still be referenced from, so the safe-delete guard loses no coverage.

### The export `schedules` key is dropped, not emptied

`ExportData` loses the field. Emitting `"schedules": {}` forever would be a
promise to a reader that the concept still exists. `FromJSON` already used `.:?`,
so an export written by an older build still parses and its schedules are
discarded — the only available outcome, since there is nowhere to put them.

`gatherExport`'s `Maybe Text` parameter existed solely to serve
`export <name> <file>`; with that command gone, all three remaining callers passed
`Nothing`, so the parameter goes too.

### The demo builds week 1 as a draft

The demo's first scheduling section becomes:

    draft create 2026-04-06 2026-04-12 --force
    draft generate 1
    draft view 1 / draft hours 1 / draft diagnose 1
    draft commit 1 initial week 1

`--force` is needed because the freeze line is yesterday and every demo date is in
April 2026 — the same reason every other `draft create` in the file already passes
it.

This is not a cosmetic substitution. `schedule create` generated slots with
`Calendar.generateWeekSlots defaultHours` and an empty calendar-hours map;
`draft generate` uses the draft's date range, per-station hours, station closures,
real pay-period bounds and already-committed calendar hours. **The demo's week-1
output changes**, and so does `demo-export.json`. That is the intended direction —
the demo now shows the scheduler the rest of the system uses.

Committing the week-1 draft consumes draft id 1, so the six later `draft`
references in the file shift from 1–6 to 2–7.

### The sidebar link is renamed now, not in the page change

`web/src/components/Sidebar.tsx` links to `/schedules`, a route that has never
existed — `path="*"` bounces it to the dashboard. It is renamed to
`/drafts` / "Drafts" here so the frontend stops naming a deleted concept. It still
bounces to the dashboard until the `/drafts` page ships, which is no worse than
today.

## Risks / Trade-offs

- **Anyone with a script calling `schedule create` or `GET /api/schedules` is
  broken with no deprecation window.** Accepted: the CLI is the only client and it
  ships from this repo, so a caller and its removal move together.
- **The `schedule` help group disappears**, and `two-level-help` names it in the
  minimum group set. The spec delta drops it; `draft` and `calendar` are already
  groups and cover the work.
- **Reviewing this diff is hard** — it is deletion across seventeen files. The
  compiler carries most of the weight: removing the four `Repository` fields and
  the `Command` constructors turns every missed call site into a type error, not a
  runtime surprise. The parts the compiler cannot check are the SQL strings, the
  demo script and the JSON fixtures, which is why verification runs the demo and
  diffs its export.
