# Project status and next steps

**Last updated:** 2026-08-16 · at commit `c07dd7b` on `master`

Working notes for whoever (or whatever) picks this up next. This file is the
authoritative record of agreed next steps, deliberately kept in the repo so it
is reachable from a fresh clone, from a container, and by a new collaborator.
Nothing here depends on machine-local state.

**Keep it current.** If you finish an item, delete it from here rather than
leaving a stale claim behind.

---

## Where things stand

The admin web UI has pages for skills, stations, workers, shifts, and a
read-only calendar. The CLI remains a first-class client. See
`openspec/web-interface-roadmap.md` for the intended sequence and
`openspec/changes/archive/` for what has shipped (29 changes).

**Verification baseline at `c07dd7b`** — all of this was green:

- `stack clean && stack build --pedantic --test` — zero warnings
- 248 integration + 360 unit examples, 0 failures
- `cd web && npm run build` — clean
- demo runs end to end, exit 0

Two standing gotchas when you verify:

- **`npm run lint` reports 5 errors** in `web/src/hooks/useSSE.tsx` and
  `web/src/App.tsx`. These are **pre-existing**, confirmed at baseline. Not
  regressions. Fixing them is unclaimed work.
- **Warnings hide in incremental builds.** `stack test` compiles specs without
  `-Werror` and caches the objects, so a later `--pedantic` build reuses them and
  reports nothing. Only `stack clean` first gives a truthful answer. This is why
  `CLAUDE.md` insists on it — three `-Wtype-defaults` errors in
  `test/PubSubSpec.hs` hid this way and were only caught on a clean rebuild.

---

## Next steps

### 1. Structured rename events + SSE role filtering

Both touch `server/Server/EventStream.hs`; do them together.

**The non-obvious part — a client-side parser cannot work.** The rename command
string is not consistently formatted across code paths:

- REST logs names: `handleRenameSkill` in `server/Server/Handlers.hs` emits
  `skill rename <oldName> <newName>`.
- RPC and the CLI log an id: `rpcRenameSkill` in `server/Server/Rpc.hs` emits
  `skill rename <id> <newName>`.

`web/src/components/WorkerDetailPage.tsx` navigates on rename by parsing
`event.command` with a local TypeScript `shellWords` helper. It therefore fails
silently whenever the rename came from the CLI — the common case. Do **not**
copy that pattern into the other detail pages.

Order of work:

1. Add structured `oldName`/`newName` to the SSE payload. `EventStream.hs` builds
   the JSON object; the metadata comes from `CommandMeta` in
   `src/Audit/CommandMeta.hs`.
2. Normalise the two render sites so REST and RPC agree. This is one instance of
   a broader duplication: command strings are hand-concatenated at ~60 sites in
   `Handlers.hs` and ~46 in `Rpc.hs`, which a `render :: Command -> Text` would
   collapse.
3. Then add navigate-on-rename to `SkillDetailPage.tsx` and
   `StationDetailPage.tsx`, reading the new fields. Retire the TypeScript
   `shellWords` copy — it duplicates `src/Utils.hs` in another language.
   SSE `entityType` is `"skill"` / `"station"`; the worker page subscribes to
   both `worker` and `user` because user-level mutations affect worker rows.

**SSE has no filtering at all.** `EventStream.hs` discards the authenticated user
(`Just _user ->`), subscribes to `".*"`, and guards only on `cmIsMutation`. Every
authenticated user therefore receives every mutation event from every other user.

Harmless today because only admins use the React UI, and REST reads are still
authorization-checked — the recipient just refetches. It becomes a leak the moment
a `Normal`-role user can log into the web UI: the feed exposes the existence,
timing and entity names of admin-only mutations.

Fix: pass the resolved `User` into the subscribe callback and drop events the
subscriber may not see, mapping `cmEntityType` to a required role. Do **not**
reintroduce filtering on `ceUsername` — that was removed deliberately on
2026-05-17 because it broke legitimate cross-tab and CLI-to-browser sync.
Per-tab echo suppression is the frontend's job, via `clientId` in `Terminal.tsx`.

Note `openspec/specs/event-stream-endpoint/spec.md` is **stale** and contradicts
the code: it still requires same-user filtering. Reconcile it as part of this
change. It drifted because `openspec/changes/archive/2026-04-17-sse-gui-refresh/`
was archived with a proposal only — no spec delta, no tasks.

### 2. `/schedules` page — blocked on a product decision

The sidebar has linked `/schedules` since the dashboard shell landed. It is the
one route deliberately left unrouted, because it needs REST that does not exist:
no `POST /api/schedules`, no assign/unassign. `Service.Schedule.createSchedule`
has no REST surface at all.

**Decide first whether this page should target named schedules or drafts.**
`createSchedule` is the legacy path — it hardcodes empty closed-slots,
previous-weekend workers and calendar hours. `Service.Draft` is the richer one
(seeds from the calendar, respects pay-period bounds, station closures, exempt
hours). Building endpoints for the legacy path may be the wrong move.

Frontend groundwork is already in place: routes in `web/src/App.tsx`, class
vocabulary in `web/src/App.css`. Follow `WorkersListPage.tsx` — it is the most
recent and complete — over the skills/stations pages where they differ. The three
existing list/detail pairs are inconsistent in ~10 ways (error rendering, toasts,
404 handling, `deleteConfirm` state key naming); prefer the worker page's choices.

### 3. Shift delete orphans worker preferences

`worker_shift_prefs.shift_name` is a plain string with no foreign key or cascade,
and `sqlDeleteShift` in `src/Repo/SQLite.hs` is a bare
`DELETE FROM shifts WHERE name = ?`. Deleting a shift leaves preferences that
match nothing.

`handleDeleteShift` has no 409-reference protocol, unlike skills and stations.
The Shifts page's confirm modal currently *warns the user* about this; the schema
gap is unfixed. Consider the safe-delete / force-delete pattern already
established for skills, stations and workers.

### 4. `/api/workers` and `/api/stations` expose no ids

`Assignment` serialises worker and station as bare integers, but neither list
endpoint returns an id: `handleListWorkers` maps it away, and
`handleListStations` explicitly discards it (`pure [st | (_, st) <- stations]`).

Consequence: `web/src/api/calendar.ts` resolves names via `GET /api/export` — the
entire export dump — purely to build an id→name map. Adding `id` to those
responses, or names to `Assignment`, lets the calendar page drop that dependency.

### 5. Make the integration-test DB path unique per run

**Agreed with the user.** Every spec hardcodes a fixed absolute path in `/tmp`:
`/tmp/manars-kitchen-test-api.db` plus siblings suffixed `-audit`, `-draft`,
`-session`, `-hint-e2e`, `-calendar`, `-draft-validation`, `-hint-session`.

Two overlapping `stack test` runs therefore share database files and corrupt each
other, with SQLite reporting `disk I/O error` from stale `-wal`/`-shm`. The
failures are **wildly misleading**: 20–99 failures on identical, correct code,
including trivial assertions like "GET /api/skills returns empty list". This cost
real time twice during parallel work.

Fix: derive the path per run (process id, or `withSystemTempDirectory` from
`temporary`) instead of a module-level constant, and clean up in a bracket. Keep a
recognisable prefix so a failed run's database can still be inspected. **Clean up
the `-wal` and `-shm` sidecars too, not just the `.db`.**

If you hit broad unrelated test failures, suspect this before suspecting a
regression.

### 6. Smaller backlog

- **Station safe-delete ignores schedule assignments.** `safeDeleteStation`
  checks worker station preferences and station required skills only. Assignment
  checking was deferred because "active schedule" needs defining. Revisit
  alongside item 2.
- **The `demo` command is wrong for the web terminal.** It wipes the database and
  replays the audit log, which is useless on a fresh DB. The `--demo` CLI flag
  reading `demo/restaurant-setup.txt` is what actually populates sample data. A
  web-terminal-friendly version would run the script server-side, or offer a
  "populate with sample data" command.
- **Import does not refresh the GUI.** `Handlers.hs` publishes `import data`,
  which classifies as entityType `import-export`; no web component subscribes to
  it. See `notes.txt` for the original observation.
- **The `/shifts` and `/calendar` pages have never run against a live server.**
  Both were type-checked and reasoned about, not exercised. The demo DB has zero
  rows in `calendar_assignments` and `calendar_commits`, so the calendar needs
  seeding before it shows anything. **Verify these in the real app before
  trusting them.**

---

## Larger debt, deliberately untouched

Catalogued during a survey; re-check before acting, as line counts drift.

- `src/CLI/App.hs` is ~2700 lines, of which `handleCommand` is a single
  ~1600-line case expression. Splitting it into per-entity modules as pure code
  motion would make everything below easier to review.
- **Command knowledge is duplicated across eight sites**, including
  `parseCommand`, `handleCommand`, `isMutating`, `classify`/`render`,
  `commandEntityMap`, and the hand-concatenated command strings in `Handlers.hs`
  and `Rpc.hs`. A `render :: Command -> Text` is the highest-leverage fix and
  also resolves item 1's format divergence.
- `isMutating` in `src/CLI/App.hs` still duplicates `cmIsMutation` in
  `src/Audit/CommandMeta.hs`. They already diverged once, silently classifying
  `worker view` and `station view` as mutations (fixed in `9538944`). The only
  guard is a hand-maintained consistency table in `test/AuditSpec.hs`, so a newly
  added view command could diverge again unnoticed.
- REST and RPC are near-duplicates — 52 identically-named handler pairs. Since
  `/rpc/execute` exists, deleting most of `RpcAPI` may beat maintaining both.
- `cli/CLI/RpcClient.hs` has ~54 "not yet supported in remote mode" branches, and
  three commands silently render the wrong view in remote mode.
- ~1900 lines of hspec live inside `src/`, which forces `hspec` and `QuickCheck`
  to be **library** dependencies. Moving them to `test/` is mechanical and
  per-module.
- `Either String` is the universal error type. `src/Service/Worker.hs` shows the
  better pattern with a `WorkerNotFound`/`NotAWorker` sum type.
- `server/Server/Json.hs` (~1200 lines) splits cleanly by entity — an easy win.

---

## Working notes

**Build and test.** See `CLAUDE.md`. `stack` only, never `cabal`. Clean build
before declaring done, for the reason in the baseline section above.

**Running without permission prompts.** `./dev/claude-container.sh yolo`. The full
analysis, assumptions and limits are in `dev/docker/README.md` — read it before
relying on the setup, particularly §3 (the undocumented behaviour it depends on)
and §6 (what it does not protect).

**Git guardrails are active** and block destructive git commands via a
`PreToolUse` hook. Two consequences worth knowing up front:

- `wt merge` is allowed — it is local-only. `wt step push` is blocked.
- **The hook inspects the entire command line, so it false-positives on prose.**
  A commit message or test fixture that merely mentions a blocked command gets
  blocked. Workaround: put the text in a file — `git commit -F <file>`, prompts
  via stdin. **Do not obfuscate a command to get around the hook**; move the text
  or amend the pattern list deliberately.

**Parallel agents in worktrees.** `.worktreeinclude` and `.config/wt.toml` are
committed. Measured costs and caveats are in `dev/docker/README.md` §5.4 and
§5.6. Operationally:

- Worktrunk project config needs a one-time interactive `wt config approvals add`
  that an agent cannot grant. Agents should use
  `wt switch -c <branch> --no-cd --no-hooks` plus an explicit
  `wt step copy-ignored`.
- `wt list`'s would-conflict pre-flight needs git ≥ 2.38; a host on 2.34 reports
  `fatal: unknown rev --write-tree`. The container's git 2.43 fixes it.
- **The pattern that worked:** own the shared spine in the primary worktree first
  (routes, CSS, cross-cutting types), *then* fan agents out onto leaf files, each
  with an explicit list of files it owns and files it must not touch. Four agents
  worked concurrently this way with zero merge conflicts. Note that worktrees
  isolate source but **not** `/tmp` — see item 5.

---

## Open questions

1. Item 2 needs the named-schedules-vs-drafts decision before any endpoint work.
2. `.agents/`, `.memsearch/` and `skills-lock.json` are untracked and are
   probably `.gitignore` candidates.
