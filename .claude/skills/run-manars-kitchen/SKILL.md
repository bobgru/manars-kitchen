---
name: run-manars-kitchen
description: Build, run, and drive Manar's Kitchen — the Haskell server and CLI plus the React admin UI. Use when asked to start the app or server, run the web UI, screenshot or click through a page, drive the CLI non-interactively, run the demo, or run the test suites.
---

Two surfaces, two handles. The **web UI** is driven by Playwright scripts against
headless Chromium in `web/e2e/`, run from `web/`:

| script | drives | database it needs |
|---|---|---|
| `npm run e2e:drafts` | `/drafts` | **fresh** — asserts on draft #1 and the empty list |
| `npm run e2e:draft-detail` | `/drafts/:id` | **demo-seeded**, and a fresh copy per run |
| `npm run e2e:calendar` | `/calendar` | **demo-seeded** |

The **CLI** is driven by `stack exec manars-cli -- --demo <script>`, which replays
a file of commands non-interactively; that is the only way to exercise CLI
behaviour without a human at a prompt.

All paths below are relative to the repo root.

**Verified on macOS (Darwin, arm64) on 2026-09-05.** The build and test steps are
also known to work in the Linux x86_64 dev container (see `dev/docker/README.md`
and `docs/STATUS.md`); the browser driver has **not** been run there, and would
need `npx playwright install chromium` plus whatever shared libraries headless
Chromium wants on that image.

## Prerequisites

Nothing was installed at the system level for this. `stack`, `node` and `npm`
were already present:

```bash
stack --version   # 3.11.1
node --version    # v24.20.0
npm --version     # 11.19.0
```

## Setup

```bash
cd web && npm install
npx playwright install chromium   # one-time, ~94 MB; must run from web/
```

No env vars. No API keys. The server creates a default `admin`/`admin` user on a
fresh database, which is what the driver logs in with.

## Build

Read `CLAUDE.md` before changing any of these flags. **Never pass `--fast`** — it
alters the GHC options, so nothing already compiled matches and stack rebuilds
the world, throwing away the dependency build baked into the container image.

```bash
stack build --pedantic
cd web && npm run build       # tsc -b && vite build
```

## Run (agent path): the web UI

Three steps — API server, dev server, driver. The driver asserts on draft ids
starting at `#1` and on the empty-list state, so **the database must be fresh**.

```bash
# 1. API server on 8080, on a throwaway database
rm -f /tmp/mk-run.db /tmp/mk-run.db-wal /tmp/mk-run.db-shm
(stack exec manars-server -- /tmp/mk-run.db > /tmp/mk-server.log 2>&1 &)
timeout 40 bash -c 'until curl -s -o /dev/null http://localhost:8080/api/config; do sleep 1; done'

# 2. Vite dev server on 5173, which proxies /api and /rpc to 8080
cd web
(npm run dev > /tmp/mk-vite.log 2>&1 &)
timeout 60 bash -c 'until curl -sf http://localhost:5173/ >/dev/null; do sleep 1; done'

# 3. Drive it
npm run e2e:drafts
```

Stop, before relaunching:

```bash
lsof -ti:5173 -sTCP:LISTEN | xargs -r kill
pkill -f manars-server
```

Screenshots → `web/e2e/screenshots/` (gitignored). Logs → `/tmp/mk-server.log`,
`/tmp/mk-vite.log`.

`npm run e2e:drafts` walks ten states of `/drafts` — empty list, the frozen-range
refusal, the client-side bad-range guard, create, generate, two overlapping
drafts, the commit 409, the forced commit and the resulting "calendar replaced"
warning, the discard confirmation, and empty again. It prints one line per state
and exits non-zero on an unexpected console error. **Look at the screenshots.** A
blank frame means the app never rendered and the assertions would not
necessarily have caught it.

`npm run e2e:draft-detail` and `npm run e2e:calendar` need a **demo-seeded**
database instead, which is a different recipe — and one with a trap in it:

```bash
stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay
sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);"   # <-- do not skip
rm -f /tmp/mk-detail.db /tmp/mk-detail.db-wal /tmp/mk-detail.db-shm
cp demo-db/demo.db /tmp/mk-detail.db
(stack exec manars-server -- /tmp/mk-detail.db > /tmp/mk-server.log 2>&1 &)
```

`e2e:draft-detail` walks seven states — the pin-seeded draft, the generated grid,
manufactured violations with a flagged chip, a sibling draft committed over the same
week, the resulting replaced-calendar warning, committing from the detail page and
the confirmation handed to the list, and the terminal state for a draft id that does
not exist. It mutates the database, so **re-run it against a fresh copy**.
`e2e:calendar` walks four — the live month, a history snapshot, and both branches of
the range guard.

To drive a different page, copy the closest of the three — each header lists the
prerequisites it does not manage.

## Run (agent path): the CLI

`--demo <file>` replays one command per line against a database it wipes first
(`demo-db/demo.db`), echoing each command and its output. This is the harness for
CLI behaviour:

```bash
printf 'draft create 2026-04-06 2026-04-12 --force\ndraft revalidate 1\nhelp draft\n' > /tmp/check.txt
stack exec manars-cli -- --demo /tmp/check.txt --no-delay
```

`--no-delay` runs flat out; `--delay 600` puts 600 ms between commands, which is
needed when the behaviour under test depends on distinct millisecond timestamps
(draft `last_validated_at` versus a calendar commit's `committed_at`, for
instance).

The project's own scripted demo is the same mechanism:

```bash
stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay
```

It ends with `Replay complete.` and reports 199 assignments / 159 unfilled. Use
`stack exec` rather than `make demo` — see Gotchas.

## Run (human path)

`stack exec manars-cli` opens the interactive prompt. `make server` and
`cd web && npm run dev` then a browser at <http://localhost:5173>. Neither is
usable from an agent session; the driver paths above exist for that reason.

## Test

Warnings hide in incremental builds, so `stack clean` first or the answer is not
truthful. Run the two suites **sequentially** — see Gotchas.

```bash
stack clean
stack build --pedantic
stack test --pedantic manars-kitchen:test:manars-kitchen-unit-test
stack test --pedantic manars-kitchen:test:manars-kitchen-integration-test
```

As of 2026-09-05: 386 unit examples, 0 failures, 1 pending (a known optimizer
divergence, `docs/STATUS.md` item 6); 271 integration examples, 0 failures. The
only warnings in a clean build are three `ld: warning: -U option is redundant`
lines from the macOS linker.

## Gotchas

- **Polling `/api/config` with `curl -sf` never succeeds.** Unauthenticated reads
  return 401, so `-f` treats a healthy server as a failure and the loop spins
  until it times out. Poll with `curl -s -o /dev/null` and ignore the status.
- **`manars-server` serves no HTML.** It is the API only; there is no static-file
  route. The UI exists solely through the Vite dev server, which is why the
  driver targets 5173 and not 8080.
- **The driver must run from `web/`.** Node resolves ESM imports relative to the
  script's own directory, so a copy in `/tmp` fails with
  `ERR_MODULE_NOT_FOUND: Cannot find package 'playwright'` even though it is
  installed in `web/node_modules`.
- **`npm run e2e:drafts` needs a fresh database every time.** Rerunning against a
  database that already holds drafts fails at the first `No drafts` assertion.
  Delete the `.db` and restart the server, not just the driver.
- **Checkpoint the demo's WAL before copying its database.** `--demo` leaves most
  of what it wrote in `demo-db/demo.db-wal`, so `cp demo-db/demo.db …` followed by
  deleting the sidecars yields a database with **zero** calendar rows — 1020
  assignments and 5 commits silently gone. Every assertion in a demo-seeded driver
  then fails for a reason that has nothing to do with the page under test. Run
  `sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);"` first. This is also
  why `docs/STATUS.md` claimed for months that the demo DB had an empty calendar.
- **`fullPage: true` does not capture these pages.** The app shell scrolls its
  content pane internally, so a full-page screenshot stops at the terminal and
  anything below the fold — a whole violations table, for instance — is missing.
  Screenshot the element instead: `locator.screenshot({ path })`.
  `e2e/draft-detail.mjs` has a `shotOf` helper.
- **Name the three database files rather than globbing them.** Under zsh an
  unmatched `rm -f /tmp/mk-run.db*` is a fatal `no matches found` and the `rm`
  never runs, so a cleanup line that looks fine on a dirty machine breaks on a
  clean one. SQLite leaves `<db>`, `<db>-wal` and `<db>-shm`; delete all three or
  the next run reads stale WAL contents.
- **The login form has no placeholders.** `getByPlaceholder` times out;
  `getByLabel("Username")` / `getByLabel("Password")` work.
- **`getByText("#1")` is ambiguous.** It also matches the `Created draft #1.`
  toast, and Playwright's strict mode fails. Use
  `getByRole("cell", { name: "#1", exact: true })`.
- **Two of the driver's steps provoke deliberate 409s** (frozen range, overlapping
  commit), which Chromium logs as `Failed to load resource`. The driver filters
  those; a copy for another page must do the same or it will always "fail".
- **`stack test ... | tail` swallows the exit code.** A pipeline's status is the
  last command's, so `stack test … | tail && stack test …` runs the second suite
  even when the first failed. Pipe nothing, or check `PIPESTATUS`.
- **Don't use `make demo` / `make fast-demo` after a `--pedantic` build.** Their
  `build` dependency is plain `stack build`, which flips the GHC options back and
  rebuilds the whole tree. Run `stack exec manars-cli -- --demo …` directly.
- **Never run two `stack test` invocations at once.** Every integration spec
  hardcodes a fixed `/tmp` database path, so concurrent runs corrupt each other
  and report 20–99 wildly misleading failures on correct code
  (`docs/STATUS.md` item 5).
- **An uncaught exception in one CLI command aborts the whole `--demo` replay**,
  and the remaining commands are silently skipped. A short replay that ends
  without `Replay complete.` died partway.

## Troubleshooting

- **`ERR_MODULE_NOT_FOUND: Cannot find package 'playwright'`**: the driver is
  outside `web/`. Run it from `web/`.
- **`locator.waitFor: Timeout 30000ms exceeded … waiting for getByText(/No drafts/)`**:
  the database is not fresh. `pkill -f manars-server`, delete the `.db` and its
  `-wal`/`-shm` siblings, restart.
- **`locator.fill: Timeout … waiting for getByPlaceholder(/username/i)`**: wrong
  selector for the login form; use `getByLabel`.
- **`strict mode violation: getByText('#1') resolved to 2 elements`**: the toast
  and the table cell both match. Narrow to `getByRole("cell", …)`.
- **`SQLite3 returned ErrorConstraint while attempting to perform step: FOREIGN KEY constraint failed`**:
  a raw entity id reached a write without an existence check. This was fixed for
  skill ids in `a3f9b8f` (`withSkillIds` in `src/CLI/App.hs`); if it reappears,
  something else is passing an unchecked id through `repoSaveSkillCtx`.
- **Vite serves but the page is blank**: check `/tmp/mk-vite.log` for a transform
  error, and the browser console output the driver prints. A route can render its
  shell while every fetch fails.
