# Project status and next steps

**Last updated:** 2026-08-30 · on `master` at commit `eae0084`, plus the
uncommitted item 1 step 3 split described below

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
`openspec/changes/archive/` for what has shipped (33 changes).

**The project no longer uses OpenSpec.** Switched 2026-08-30 to `grill-with-docs`:
grill the design first, then capture what was settled as glossary entries in
`CONTEXT.md` and, where a decision is hard to reverse, an ADR in `docs/adr/`. See
`CLAUDE.md`. Do not create new `openspec/changes/` entries — `openspec/specs/` and
`openspec/changes/archive/` stay as the record of what shipped and are still worth
reading, they are just no longer extended. This file remains the authoritative
next-steps record.

**Named schedules no longer exist.** Removed 2026-08-24 in `08a2d6d`. Every
schedule is built inside a draft and reaches the calendar by committing that
draft. If you find a reference to `schedule create`, `assign`, `unassign` or
`calendar commit <name> ...` anywhere, it is stale documentation. The
`schedules` and `assignments` tables are still readable in any database created
before that commit — the `CREATE TABLE` statements went, no `DROP TABLE`
replaced them — so nothing in the code may name either table again.

**The draft lifecycle rules live in `Service.Draft`, not in the CLI.** Moved
2026-08-24. `createDraft` takes a `CreateDraftOpts` carrying the caller's force flag
and unfrozen ranges and returns `Either CreateDraftError Int`, so the freeze-line
check runs for every client; `commitDraft` returns a `CommitOutcome` reporting
whether the range covered frozen dates and deletes **every** session's what-if row
for the draft; `generateDraft` takes `Maybe (Set WorkerId)` and resolves `Nothing`
to the active workers via `activeWorkerIds`. Two consequences to keep in mind:

- **A REST or container-CLI caller cannot force past the freeze line.** Force and
  unfreezes are session state that never crosses the wire, so `POST /api/drafts`
  over frozen dates is a 409 carrying `error`, `freezeLine`, `frozenFrom` and
  `frozenTo`, and `draft create ... --force` in `--remote` mode is refused —
  `cli/CLI/RpcClient.hs` still discards the flag, deliberately. Unfreeze remains
  local-CLI-only; `POST /api/calendar/unfreeze` is still a no-op stub.
- **An absent `workerIds` is not an empty one.** `Nothing` means the active workers,
  `Just []` means schedule nobody, and both are honoured. Container-mode
  `draft generate` used to send `[]` and so silently scheduled nobody; fixed at the
  same time.

Anything that tests these has to pick dates relative to the run, because the freeze
line is computed from the current date and every fixed 2026 fixture date is now
frozen. `test/ApiSpec.hs` has a `futureWeek` helper for that; the suites that need
the fixed Mon–Fri reasoning use a `createForced` helper instead.

**`CONTEXT.md` at the repo root is the glossary of record**, and `docs/adr/` holds the
decisions that a reader would otherwise wonder about. Read both before touching
scheduling code — several terms in this codebase do not mean what they appear to mean,
and ADR 0002 exists because two of them are outright swapped.

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

**Verification baseline at the draft-validation split** — everything above, plus the
service-layer and optimizer moves, the structured-rename and SSE role-filtering work,
and the named-schedule removal. All of this was green, with `LANG` unset:

- `stack clean && stack build --test` — zero GHC warnings (`-Wall` is set on every
  stanza in `manars-kitchen.cabal`, so no extra flag is needed to surface them)
- 258 integration + 379 unit examples, 0 failures, 1 pending (the weekend
  divergence in item 6). The integration count fell to 255 with the named-schedule
  tests removed, then rose again with the freeze-line and active-worker coverage; the
  unit count rose from 373 to 379 with the step 3 coverage.
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

### 1. `/drafts` page — decided 2026-08-23, ready to implement

**No longer blocked.** The page targets **drafts and the calendar**; the
named-schedule path is removed. See ADR 0001, 0002 and 0003 for the reasoning.

Four premises in the earlier version of this item were wrong, and are worth stating
so nobody re-derives them:

- **The draft REST surface already exists and works** — list, create, get, generate,
  commit, discard (`server/Server/Api.hs:55-63`, handlers `Handlers.hs:274-311`).
  There was never a need for `POST /api/schedules`.
- **The one missing read is a draft's assignments.** `GET /api/drafts/:id` returns
  metadata only. Nothing exposes `repoLoadDraftAssignments`, so a browser can see a
  draft only by re-running `generate`, which mutates it.
- **There was never a `/schedules` route.** `web/src/App.tsx` has none and
  `path="*"` redirects to `/`, so the sidebar link silently bounced to the dashboard.
  The claim that "routes are already in place" was false. The sidebar link now reads
  "Drafts" → `/drafts` and bounces the same way until step 6 lands; the CSS
  vocabulary in `App.css` is the only other thing that exists.
- **The REST draft endpoints skipped rules the CLI enforces**, because those rules
  lived in `src/CLI/App.hs` rather than the service layer. Mostly fixed on 2026-08-24
  — see the service-layer paragraph above — and the two draft handlers now call
  `logRest`, so create and generate finally reach the audit log, the terminal pane
  and the SSE feed. What remains in the CLI is **validation before viewing**: `draft
  open` prunes as a side effect of reading (`App.hs:324`), which was step 3, now
  shipped.

#### Decisions

| Decision | Answer |
|---|---|
| Force / unfreeze over REST | Not built. Creating a draft over frozen dates returns 409. Unfreeze stays CLI-only. |
| Route and label | "Drafts" → `/drafts`. No redirect from `/schedules` — nothing ever served it. |
| Overlapping drafts | Allowed freely. A draft is an experiment sandbox; creating one must never be refused. |
| Overlapping commits | 409 naming the overlapping drafts; `POST /api/drafts/:id/commit/force` proceeds. |
| Cross-draft conflict detection | Out of scope. Competing experiments are meant to disagree. |
| Candidate workers for generate | `workerIds` becomes optional, defaulting server-side to active workers. |
| Manual per-slot editing | Out of scope, and when it comes it goes through what-ifs — never a draft-level assign endpoint, which would bypass rebase and validation. |

#### Steps, in order

Each is independently shippable. Two preliminaries are done, and so are steps 1, 2
and 3:

- ~~**Expose ids on `/api/workers` and `/api/stations`**~~ — shipped as `a9c4d28`.
  `GET /api/stations` returns a new `StationResp` with `id`; `GET /api/workers` returns
  `id` on each summary; `web/src/api/calendar.ts` no longer fetches `/api/export` to
  build its id→name maps.
- ~~**Move the optimizer into `draft generate`**~~ — not in the original list, and a
  prerequisite for the step below. `schedule create` was the *only* caller of
  `Service.Optimize.optimizeSchedule` and the only publisher of a `ProgressEvent`, so
  removing the named-schedule surface would have orphaned `Service.Optimize`,
  `Domain.Optimizer` and every requirement in the `progress-events` capability.
  `generateDraft` now takes a `TopicBus ProgressEvent` and calls `optimizeSchedule`;
  the CLI's `[opt]` printer moved into a `withProgressPrinting` helper in
  `src/CLI/App.hs`. No behaviour change at the default `opt-enabled` of `0`. **This
  surfaced a pre-existing defect — see item 6.**

1. ~~**Remove the named-schedule surface.**~~ — shipped as `08a2d6d`, and pure removal
   as intended once the optimizer had moved. Worth carrying forward: the demo now
   builds week 1 inside a draft, so **every draft id in `demo/restaurant-setup.txt`
   shifted by one** — a later edit that inserts or removes a `draft create` has to
   shift them again. `export.json` and `demo-export.json` are gitignored, so the demo
   regenerates them and no fixture is committed. `etSchedule` survives in
   `src/Audit/CommandMeta.hs` as the entity type for the group-less commands (`help`,
   `quit`, `audit`, `replay`, `demo`, `use`, `context`) — it is not dead code.
2. ~~**Push the draft lifecycle rules into the service layer.**~~ — shipped as
   `a4a2d30`: freeze check into `createDraft`, what-if-session cleanup and auto-refreeze
   into `commitDraft`, `logRest` on create and generate, `workerIds` optional. The
   details worth carrying forward are in the service-layer paragraph near the top of
   this file. This was originally the first half of a larger step; the validation split
   is now step 3 on its own, per `CLAUDE.md`'s independently-shippable rule.
3. ~~**Split `validateDraftAgainstCalendar`.**~~ — shipped 2026-08-30.
   `Service.DraftValidation` now exports `isDraftStale` (takes a loaded `DraftInfo`,
   not an id), `computeDraftViolations` (no writes, **no staleness gate**) and
   `pruneDraftViolations` (the gate, then the computation, then the removal — exactly
   what the old function did). `validateDraftAgainstCalendar` is gone rather than kept
   as an alias; `src/CLI/App.hs` was its only production caller and now calls
   `pruneDraftViolations`. A private `validateDraft` holds the shared body and returns
   the draft's schedule alongside the violations, so the pruning path does not load the
   assignments twice.

   **The gate hides real violations, and now there is a test that says so.** Only a
   *calendar commit* makes a draft stale, so anything else that invalidates an
   assignment — an approved absence, a revoked skill, a changed hour limit — is invisible
   to `pruneDraftViolations` for as long as the calendar sits still. `test/DraftValidationSpec.hs`
   pins this down with an approved absence over a draft assignment: `pruneDraftViolations`
   returns `[]` while `computeDraftViolations` reports the conflict. Step 5's endpoint
   must use the latter, and the deferred draft-workflow question below should treat the
   staleness trigger as too narrow, not just wrongly-responding.
4. **Allow overlapping drafts** — delete `repoCheckDraftOverlap` and its guard, spec
   deltas removing the `Non-overlapping date ranges` requirement from `draft-session`
   and the matching scenarios from `draft-shortcuts` — plus the commit 409 and
   `commit/force`, and extend the staleness report to say *the calendar for these
   dates was replaced by draft #N*.
5. **`GET /api/drafts/:id/assignments`** returning `{assignments, violations}`. **The
   GET must not mutate** — it reports violations without deleting them or bumping
   `last_validated_at`, which is what `computeDraftViolations` is for (step 3). Pruning
   gets an explicit `POST /api/drafts/:id/revalidate`, which calls
   `pruneDraftViolations`. `isDraftStale` is there if the response should also say
   whether the calendar has moved.
6. **`/drafts` list page** — create, generate, commit (with the 409/force flow),
   discard. No assignment grid.
7. **Draft detail page** — the assignment grid, violations alongside assignments.

For both page steps, follow `WorkersListPage.tsx` — the most recent and complete — over
the skills/stations pages where they differ. The three existing list/detail pairs are
inconsistent in ~10 ways (error rendering, toasts, 404 handling, `deleteConfirm` state
key naming); prefer the worker page's choices. **Exercise them against a live server**,
not just `tsc` — see the last bullet of item 7.

### 2. The problem view — designed 2026-08-30, not started

The `/` dashboard becomes a visualization of **problems** across workers, stations and
slots. The full design and the rejected alternatives are in **ADR 0004**; the vocabulary
is in `CONTEXT.md` under "Problems". Read both before starting — the shape is not
obvious from the code, and three of the pieces do not exist yet.

What this needs, roughly in dependency order:

1. **Generalise the validation core.** `Service.DraftValidation.validateDraft` is private
   and takes a `DraftInfo`; it needs to take a `Schedule` plus a `(Day, Day)` range so
   the calendar slice can be fed through it. This is the "virtual default draft" — there
   is deliberately no default draft *row*, see the ADR. Today's step 3 split already
   isolated the body, so this is close to mechanical.
2. **Compromise has no implementation at all.** The soft score lives only inside the
   optimizer's hill climbing (`Domain.Scheduler.scoreSlotWorker`, seven components, some
   of them penalties) and reaches no client. Deriving per-assignment compromises from the
   penalty components is new work, and each one owes the detail pane a sentence — "Ana
   got the same station three days running", not "score 0.31".
3. **A nullable zone label on `Station`**, for grouping the station view. Not
   coordinates; the floor plan is deferred in the ADR.
4. **An auto-approve flag on `AbsenceType`**, same shape as the existing `atYearlyLimit`,
   so a sick call submitted from a mobile client takes effect immediately instead of
   waiting for approval. **This lets a worker grant themselves an absence**, because
   `handleRequestAbsence` is `requireSelfOrAdmin` — intended for sick leave, but it is an
   authorization change, so do not slip it in silently.
5. **The three visualizations plus the horizon control.** Projections of one problem set;
   cells aggregate to most-severe plus earliest affected date.

Two things to carry forward. The horizon is a **required input**, not a filter applied
afterwards — a problem set without a date range is meaningless. And the reason this is
not built on persisted violations is the sick-call case: an approved absence invalidates
calendar assignments *without changing the calendar*, so anything recomputed on write
misses it. That is the same blind spot as the staleness gate in item 1 step 3.

### 3. The demo is not representative of a working restaurant

`make fast-demo` reports **199 assignments, 159 unfilled**. A real restaurant is mostly
staffed, so a demo that is 80% holes gives a false picture of what the problem view will
show and makes it impossible to tell a real regression from the fixture. Either fix the
fixture so it fills, or — better — split it into a few named scenarios (fully staffed;
one worker calls in sick; a station reopens understaffed) so each surface can be
exercised against the state it is meant to display.

Note if you edit `demo/restaurant-setup.txt`: **every draft id in it is positional**, so
inserting or removing a `draft create` shifts the rest.

### 4. Shift delete orphans worker preferences

`worker_shift_prefs.shift_name` is a plain string with no foreign key or cascade,
and `sqlDeleteShift` in `src/Repo/SQLite.hs` is a bare
`DELETE FROM shifts WHERE name = ?`. Deleting a shift leaves preferences that
match nothing.

`handleDeleteShift` has no 409-reference protocol, unlike skills and stations.
The Shifts page's confirm modal currently *warns the user* about this; the schema
gap is unfixed. Consider the safe-delete / force-delete pattern already
established for skills, stations and workers.

### 5. Make the integration-test DB path unique per run

**Agreed with the user, and still open.** Do not be misled by commit `455e48b`, whose
message reads "Fix integration test coupling by path" — that commit actually carried the
SSE role-filtering and structured-rename work. All eight paths below are still
hardcoded.

Every spec hardcodes a fixed absolute path in `/tmp`:
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

### 6. The optimizer diverges on any date range containing a Saturday

**Found 2026-08-23 while moving the optimizer into `draft generate`.** Pre-existing,
and unreachable at the default `opt-enabled` of `0` — which is the only reason nobody
has hit it. Once optimization is switched on, a date range containing a Saturday never
returns: the process allocates about 1 GB/s until the OOM killer ends it.

Measured against a one-station, nine-worker fixture (the pending test in
`test/DraftSpec.hs` records the same table):

| range | result |
|---|---|
| Apr 6–10 2026 (Mon–Fri) | returns at the 1s limit |
| Apr 13–17 2026 (Mon–Fri) | returns at the 1s limit |
| Apr 6–12 2026 (Mon–Sun) | OOM-killed after ~17s / 17 GB |
| Apr 11 2026 alone (Sat) | OOM-killed |

It is the presence of a Saturday, not the size of the range. Two facts narrow it
sharply:

- With `opt-time-limit-secs` at `0.0001` — which makes `hardPhase` return on its first
  clock check, before any `iteratedGreedyStep` call — a full week finishes in 0.12s.
- `bestOfStrategies` runs all five greedy strategies at magnitude 0 over that same week
  without trouble, and plain `draft generate` (`opt-enabled 0`) always has.

So the divergence is inside `iteratedGreedyStep`'s perturbed rebuild —
`buildScheduleFromPerturbed` with a non-zero magnitude — on the weekend-constraint
path, and the time limit cannot interrupt it because `hardPhase` only checks the clock
*between* iterations. Note also that `hardPhase` picks a random one of the five
strategies per iteration, so the first thing to establish is which strategy diverges;
`WorkerFirst`'s `assignWorkerToAllBlocks` recursion is the obvious suspect but it is
guarded by `isShiftCandidate`, which does require one assignable slot, so that guard
appears sound and the cause is probably elsewhere.

Whoever picks this up: a clock check *inside* the rebuild, or an iteration cap, would
turn an OOM into a slow response — worth having regardless of the root cause, because a
`POST /api/drafts/:id/generate` that OOMs takes the server down with it.

### 7. Smaller backlog

- **Station safe-delete ignores assignments.** `safeDeleteStation` checks worker
  station preferences and station required skills only. Assignment checking was
  deferred because "active schedule" needed defining; now that drafts are the only
  answer, the two tables to check are `calendar_assignments` and
  `draft_assignments` — the same pair `safeDeleteWorker` already counts. Revisit
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

## Deferred: revisit the admin draft workflow

**Agreed 2026-08-23.** Assume the current behaviour is correct while item 1 is carried
out, then take this up. Written down so the question is not lost.

**There is no function that rebases a draft onto a moved baseline calendar.** Two
things occupy that space and neither does the job:

- `Service.HintRebase` rebases a **what-if session** against the **audit log** —
  `classifyChange :: Int -> AuditEntry -> [Hint] -> ChangeCategory`, returning
  `UpToDate | AutoRebase n | HasConflicts [...] | SessionInvalid`. It never examines
  the draft's assignments. This is what `what-if rebase` and `POST /api/hints/rebase`
  do, and what the `hint-rebase` spec describes.
- `validateDraftAgainstCalendar` **prunes**. When the calendar has moved, it deletes
  every assignment that no longer validates —
  `repoSaveDraftAssignments repo draftId cleanedSched` — and leaves the holes for the
  admin to refill by re-running `draft generate`
  (`src/Service/DraftValidation.hs:131-152`, `pruneDraftViolations`).

The specific concerns:

1. **Pruning is not rebasing.** A moved calendar should arguably produce a *proposed*
   updated draft the admin can accept or reject, not silent deletion.
2. **Reading mutates.** Pruning fires as a side effect of `draft open`
   (`App.hs:324`), so viewing a draft changes it. Item 1's steps 4 and 6 contain that
   damage — they stop the browser inheriting it — but do not fix it.
3. **Violations are not durable.** They are returned once and never persisted, so the
   record of what was removed and why exists only in whatever output happened to see
   it.
4. **Overlapping drafts raise the stakes.** Once drafts may overlap, committing one
   prunes its siblings the next time they are opened — the right trigger, the wrong
   response, per (1).
5. **The look-back window is narrow.** Validation examines the seven days *before* the
   draft's start (`DraftValidation.hs:165-166`), so calendar assignments inside the
   draft's own range are never compared against it. That is why "the calendar for my
   dates was just replaced" reports nothing today, and why item 1 step 4 has to add
   that message separately.

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

**The container image now owns the Haskell toolchain.** Changed 2026-08-30. GHC and
every dependency are built into the image (`stack setup` + `stack build
--only-dependencies` over just `stack.yaml`, `stack.yaml.lock`,
`manars-kitchen.cabal` and `Setup.hs`, so Docker's layer cache reuses the lot when
those are unchanged). **The host's `~/.stack` is no longer mounted** — it would
shadow all of it, and the old arrangement assumed a Linux host of matching
architecture with GHC in `~/.stack/programs`, none of which holds on macOS. The
build context is now the repo root, with a new `.dockerignore`. Cold build ~196s
plus GHC download, warm rebuild 1.3s, image 5.98 GB. Details and measurements in
`dev/docker/README.md` §5.4.

**One thing still unfixed: the launcher does not work on macOS.** `CONTAINER_HOME`
is `"$HOME"`, i.e. `/Users/<user>`, while the image's `HOME` is `/home/<user>`, so
every derived mount lands on a path the image does not use — and a same-path
`/Users` bind mount is **silently dropped** by Docker Desktop, no error, empty
directory. The image itself builds and works on macOS; only the launcher's path
mapping is wrong. Fix and evidence in `dev/docker/README.md` §5.8.

**Git guardrails** block destructive git commands via a `PreToolUse` hook at
`~/.claude/hooks/block-dangerous-git.sh`, wired from `~/.claude/settings.json`.
**They are per-machine, and this file used to claim they were active when they
were not installed at all** — the setup had only ever been done inside the
container. Installed on the macOS host and re-verified on 2026-08-30. On a new
machine, **check before trusting it**: the hook file must exist and be
executable, and `~/.claude/settings.json` must have a `hooks.PreToolUse` entry.
There is one copy — `dev/claude-container.sh` bind-mounts the *host's* script
into the container read-only, and `preflight()` refuses to launch without it.

Four consequences worth knowing up front:

- `wt merge` is allowed; `wt step push` and `wt merge --no-hooks` are blocked.
  **The reason is not local-vs-remote** — worktrunk has no remote surface at all,
  and `wt step push` only fast-forwards a local branch. It is that `wt merge`
  runs the `[[pre-merge]]` test gate and the other two bypass it. Full reasoning
  in `dev/docker/README.md` §5.2; do not "fix" the apparent inconsistency by
  blocking `wt merge`, which was tried and reverted because it breaks the
  container workflow.
- **That gate needs a per-machine approval.** Granted on the macOS host on
  2026-08-30 with `wt config approvals add --yes` — plain `add` cannot prompt in a
  non-interactive session and just fails. It is stored in
  `~/.config/worktrunk/approvals.toml`, **machine-local and not in the repo**, so a
  new machine starts ungated. `dev/claude-container.sh` now bind-mounts that file
  read-only, which was verified safe: a read-only file mount leaves the parent
  directory writable, so worktrunk can still take its `.lock`. Check with
  `wt config approvals list`; reasoning in `dev/docker/README.md` §5.2.
- **The hook inspects the entire command line, so it false-positives on prose.**
  A commit message or test fixture that merely mentions a blocked command gets
  blocked. Workaround: put the text in a file — `git commit -F <file>`, prompts
  via stdin, and the `Write` tool rather than a shell heredoc. **Do not obfuscate
  a command to get around the hook**; move the text or amend the pattern list
  deliberately.
- **Re-installing from the `git-guardrails-claude-code` skill silently downgrades
  it.** The bundled script is a naive literal grep with no normalisation, no
  worktrunk patterns, and a `jq` call that fails *open*. See
  `dev/docker/README.md` §5.1.

**Parallel agents in worktrees.** `.worktreeinclude` and `.config/wt.toml` are
committed. Measured costs and caveats are in `dev/docker/README.md` §5.4 and
§5.6. Operationally:

- **`wt` is installed in the image now**, from upstream's prebuilt static musl
  binary, arch-selected and checksummed. It used to be bind-mounted from the host,
  which only worked when host and container shared OS and arch — on macOS it was
  Mach-O against a Linux container and every call died with `exec format error`.
  Fixed 2026-08-30; see `dev/docker/README.md` §5.7. Requires
  `./dev/claude-container.sh build`.
- Worktrunk project config needs a one-time `wt config approvals add --yes` that
  an agent cannot do interactively; granted on this host 2026-08-30 and now mounted
  into the container. Agents should use
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

None blocking. The named-schedules-vs-drafts question that used to sit here was settled
on 2026-08-23 in favour of drafts — see item 1 and ADR 0001. The one deliberately
deferred question is the draft workflow, above; it does not block item 1.
