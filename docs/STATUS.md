# Project status and next steps

**Last updated:** 2026-08-17 · at commit `2dd34fe` on `master`

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

**The SSE feed is role-filtered and carries structured rename fields.**
`eventVisibleTo` in `server/Server/EventStream.hs` is the one rule: `Admin` sees
every mutation, `Normal` is denied the entity types whose REST reads are
`requireAdmin` or per-worker filtered (`user`, `worker`, `absence`,
`import-export`, `checkpoint`, `what-if`) and fails closed on an unclassified
command. Filtering is by role only — **do not reintroduce `ceUsername`
filtering**, removed deliberately on 2026-05-17 because it broke cross-tab and
CLI-to-browser sync; per-tab echo suppression is the frontend's job via
`clientId`. The payload's `oldName`/`newName` exist because a client cannot parse
a rename command: the reference is an ID in some grammars and a name in others.
`cmOldName`/`cmNewName` are event-transport only — not persisted in `audit_log`,
not reproduced by `render`. Publishers that know a name the command string cannot
carry attach it with `Audit.CommandMeta.withRenameNames`.

**Verification baseline at `2dd34fe`** plus the structured-rename and SSE
role-filtering work described above — all of this was green, with `LANG` unset:

- `stack clean && stack build --test` — zero GHC warnings (`-Wall` is set on every
  stanza in `manars-kitchen.cabal`, so no extra flag is needed to surface them)
- 259 integration + 360 unit examples, 0 failures
- `cd web && npm run build` — clean
- `cd web && npm run lint` — clean, 0 problems
- demo runs end to end, exit 0

**`npm run lint` is now clean — keep it that way.** The 5 errors that used to live
in `web/src/hooks/useSSE.tsx` and `web/src/App.tsx` are fixed: the SSE provider
moved to `web/src/components/SSEProvider.tsx` (the `react-refresh` rule forbids a
file that exports both a component and hooks), and the two hooks use
`useEffectEvent` instead of assigning to a ref during render.

One standing gotcha when you verify:

- **Warnings hide in incremental builds.** `stack test` compiles specs without
  `-Werror` and caches the objects, so a later `--pedantic` build reuses them and
  reports nothing. Only `stack clean` first gives a truthful answer. This is why
  `CLAUDE.md` insists on it — three `-Wtype-defaults` errors in
  `test/PubSubSpec.hs` hid this way and were only caught on a clean rebuild.

---

## Next steps

### 1. `/schedules` page — blocked on a product decision

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

### 2. Shift delete orphans worker preferences

`worker_shift_prefs.shift_name` is a plain string with no foreign key or cascade,
and `sqlDeleteShift` in `src/Repo/SQLite.hs` is a bare
`DELETE FROM shifts WHERE name = ?`. Deleting a shift leaves preferences that
match nothing.

`handleDeleteShift` has no 409-reference protocol, unlike skills and stations.
The Shifts page's confirm modal currently *warns the user* about this; the schema
gap is unfixed. Consider the safe-delete / force-delete pattern already
established for skills, stations and workers.

### 3. `/api/workers` and `/api/stations` expose no ids

`Assignment` serialises worker and station as bare integers, but neither list
endpoint returns an id: `handleListWorkers` maps it away, and
`handleListStations` explicitly discards it (`pure [st | (_, st) <- stations]`).

Consequence: `web/src/api/calendar.ts` resolves names via `GET /api/export` — the
entire export dump — purely to build an id→name map. Adding `id` to those
responses, or names to `Assignment`, lets the calendar page drop that dependency.

### 4. Make the integration-test DB path unique per run

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

### 5. Smaller backlog

- **Station safe-delete ignores schedule assignments.** `safeDeleteStation`
  checks worker station preferences and station required skills only. Assignment
  checking was deferred because "active schedule" needs defining. Revisit
  alongside item 1.
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
  and `Rpc.hs` (~60 sites and ~46 sites respectively). A
  `render :: Command -> Text` is the highest-leverage fix. The rename sites are
  now consistent, but only because each was fixed by hand — nothing prevents the
  next hand-written command string from diverging the same way.
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

**A host-environment trap** — hit on the bare host on 2026-08-16, absent inside
the container, and not a code problem. Recognise it fast:

- **`cannot find -lgmp` at link time.** The host has `libgmp.so.10` but no
  `libgmp.so` symlink, which lives in `libgmp-dev`. Compilation succeeds and the
  build dies at the very end, in the linker. Either `apt install libgmp-dev`, or
  point stack at a symlink you own:
  `ln -s /usr/lib/x86_64-linux-gnu/libgmp.so.10 ~/.local/lib/gmp-shim/libgmp.so`
  and pass `--extra-lib-dirs=$HOME/.local/lib/gmp-shim`. Do **not** commit that
  path into `stack.yaml` — it is machine-local.

**Encoding is handled in code, not by the locale.** Every `main` calls
`setUtf8Encoding` from `src/Utils/Encoding.hs` before anything else. Without it a
POSIX/C locale makes GHC choose ASCII for the standard handles, and the first em
dash or hspec check mark aborts the program with `commitBuffer: invalid argument
(cannot encode character '\8212')` — which reads like an IO bug, not an encoding
mismatch. Both test suites and the demo failed this way. **A new executable or
test suite needs that call too**; nothing enforces it.

**`.agents/`, `.memsearch/` and `skills-lock.json` stay untracked** — decided
2026-08-16. Do not commit them and do not add them to `.gitignore`; they are meant
to show up in `git status`. Leave them alone.

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
  isolate source but **not** `/tmp` — see item 4.

---

## Open questions

1. Item 1 needs the named-schedules-vs-drafts decision before any endpoint work.
