## Why

Three rules of the draft lifecycle live in `src/CLI/App.hs` rather than in
`Service.Draft`, so only the CLI obeys them:

- **The freeze-line check.** `createDraftWithFreezeCheck` (`App.hs:2158`) refuses
  a draft covering frozen dates unless `--force` is given.
  `POST /api/drafts` calls `Service.Draft.createDraft` directly and creates it.
  A browser admin can rewrite history the CLI protects.
- **What-if session cleanup.** `DraftCommit` deletes the persisted hint session
  for the committed draft. `POST /api/drafts/:id/commit` leaves it behind,
  pointing at a draft id that no longer exists.
- **Auto-refreeze.** After committing a draft that covered historical dates, the
  CLI clears every temporary unfreeze. REST never does, because REST has no idea
  the commit touched frozen dates.

Two smaller gaps compound it: `handleCreateDraft` and `handleGenerateDraft` never
call `logRest`, so the two operations that change a draft the most emit no audit
entry, no terminal-pane command string and no SSE event; and
`GenerateDraftReq.workerIds` is required, so every caller has to enumerate the
worker set before it can generate — including a browser that just wants "everyone
who works here".

The `/drafts` page is the forcing function. A page built on today's REST surface
would be a second, weaker client with its own rules. Pushing the rules down means
the page inherits them.

## What Changes

**`Service.Draft.createDraft` owns the freeze check.** Its signature gains a
`CreateDraftOpts` record carrying the caller's `force` flag and its active
unfreezes, and it returns `Either CreateDraftError Int` instead of
`Either String Int`. `CreateDraftError` is a sum: `DraftOverlapsExisting`, or
`DraftCoversFrozenDates FrozenRange` naming the freeze line and the frozen
sub-range. The CLI passes its `--force` flag and its unfreeze `IORef`; REST
passes `defaultCreateDraftOpts` (no force, no unfreezes) and turns the frozen
refusal into a 409 with a structured body via `throwConflictWithBody`.

Unfreezes stay CLI-only and stay in the `IORef`, as decided in `docs/STATUS.md`.
The service takes them as an argument rather than reading them, so nothing has to
be persisted for this change to be correct.

**`Service.Draft.commitDraft` owns hint cleanup and reports the refreeze.** It
deletes every persisted hint session for the draft — not just the calling
session's, which is all the CLI could reach — through a new
`repoDeleteDraftHintSessions` field. It returns `CommitOutcome` whose
`coCoveredFrozenDates` says whether the committed range included dates on or
before the freeze line. The CLI clears its unfreezes when that is `True`; a
caller with no unfreezes to clear ignores it. `discardDraft` deletes the draft's
hint sessions too, which the requirement already asked for.

**`workerIds` becomes optional.** `generateDraft` takes
`Maybe (Set.Set WorkerId)`; `Nothing` resolves to the active workers
(`repoLoadWorkerIdsByStatus repo WSActive`). `GenerateDraftReq.gdrWorkerIds`
becomes `Maybe [Int]`, absent meaning the same thing. The CLI passes `Nothing`,
which **changes CLI behaviour**: `draft generate` currently offers every user
including deactivated ones and non-worker accounts to the scheduler. That was a
defect — `worker deactivate` exists to stop exactly this — and the fix is a
by-product of having one definition of "the default worker set".

**`logRest` on create and generate.** `handleCreateDraft` and
`handleGenerateDraft` publish `draft create <from> <to>` and
`draft generate <id>`, both of which `Audit.CommandMeta.classify` already
understands as mutations.

## Impact

- `src/Service/Draft.hs` — new opts/error/outcome types, freeze check, hint
  cleanup, worker default.
- `src/Service/FreezeLine.hs` — new pure `frozenRangeFor`, so the decision is
  testable without IO.
- `src/Repo/Types.hs`, `src/Repo/SQLite.hs` — `repoDeleteDraftHintSessions`.
- `src/CLI/App.hs` — `createDraftWithFreezeCheck` becomes a formatter over the
  service's refusal; `DraftCommit` consumes `CommitOutcome`; `DraftGenerate`
  passes `Nothing`.
- `server/Server/Handlers.hs`, `server/Server/Rpc.hs`, `server/Server/Json.hs` —
  the 409 body, optional `workerIds`, two `logRest` calls.
- Tests: fixtures on historical dates now pass `cdoForce = True`; the REST draft
  tests move onto dates relative to today, because a browser cannot force.

Not in scope, and deliberately: force or unfreeze over REST, persisting
unfreezes, allowing overlapping drafts (step 3), and the read-only violations
endpoint (step 4).
