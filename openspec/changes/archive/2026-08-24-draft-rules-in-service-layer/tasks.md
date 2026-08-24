## 1. Freeze line

- [x] 1.1 `src/Service/FreezeLine.hs`: add `frozenRangeFor :: Day -> Set (Day, Day)
  -> Day -> Day -> Maybe (Day, Day)` returning the still-frozen sub-range of a
  draft's date range, `Nothing` when nothing in the range is frozen.

## 2. Service layer

- [x] 2.1 `src/Service/Draft.hs`: add `CreateDraftOpts`, `defaultCreateDraftOpts`,
  `FrozenRange`, `CreateDraftError`, `CommitOutcome`; export all of them.
- [x] 2.2 `createDraft :: Repository -> CreateDraftOpts -> Day -> Day
  -> IO (Either CreateDraftError Int)` — freeze check first, then overlap.
- [x] 2.3 `commitDraft` returns `Either String CommitOutcome`, deletes the draft's
  hint sessions, and computes `coCoveredFrozenDates` from the freeze line.
- [x] 2.4 `discardDraft` deletes the draft's hint sessions.
- [x] 2.5 `generateDraft` takes `Maybe (Set.Set WorkerId)`; add `activeWorkerIds`
  and use it for `Nothing`.

## 3. Repository

- [x] 3.1 `src/Repo/Types.hs`: add `repoDeleteDraftHintSessions :: Int -> IO ()`.
- [x] 3.2 `src/Repo/SQLite.hs`: wire it to
  `DELETE FROM hint_sessions WHERE draft_id = ?`.

## 4. CLI

- [x] 4.1 `src/CLI/App.hs`: `createDraftWithFreezeCheck` passes `CreateDraftOpts`
  and formats `CreateDraftError`; the freeze-line message text is unchanged.
- [x] 4.2 `DraftCommit` consumes `CommitOutcome` for the refreeze; drops its own
  `repoDeleteHintSession` call but keeps clearing the in-memory session.
- [x] 4.3 `DraftDiscard` drops any hint-session cleanup it duplicates.
- [x] 4.4 `DraftGenerate` passes `Nothing` and stops enumerating `repoListUsers`.

## 5. Server

- [x] 5.1 `server/Server/Json.hs`: `gdrWorkerIds :: Maybe [Int]`; add the
  frozen-dates 409 body type.
- [x] 5.2 `server/Server/Handlers.hs`: `handleCreateDraft` passes
  `defaultCreateDraftOpts`, maps `DraftCoversFrozenDates` to
  `throwConflictWithBody` and `DraftOverlapsExisting` to `Conflict`, and calls
  `logRest`.
- [x] 5.3 `handleGenerateDraft` resolves absent `workerIds` to `Nothing` and calls
  `logRest`; `handleCommitDraft` accepts the new outcome.
- [x] 5.4 Both handlers take the `TopicBus CommandEvent`; update the server wiring.
- [x] 5.5 `server/Server/Rpc.hs`: the same four call sites.

## 6. Tests

- [x] 6.1 `test/DraftSpec.hs`, `test/DraftValidationSpec.hs`,
  `test/HintE2ESpec.hs`: force on historical fixture dates.
- [x] 6.2 `test/ApiSpec.hs`: draft tests move onto dates relative to today; add a
  test that a past range returns 409 with the freeze-line body.
- [x] 6.3 New coverage: `frozenRangeFor` unit cases; generate with no worker set
  uses active workers; commit deletes hint sessions for every session.

## 7. Specs

- [x] 7.1 `draft-session`: create/generate/commit requirements state where the
  rules live and that `workerIds` is optional.
- [x] 7.2 `freeze-line`: the create requirement describes the actual refusal (no
  interactive y/N), and applies to REST as a 409.
- [x] 7.3 `hint-persistence`: cleanup covers every session for the draft and
  happens in the service layer.
- [x] 7.4 `rest-api-endpoints`: draft create and generate publish GUI commands.

## 8. Verification

- [x] 8.1 `stack clean && stack build --test` with zero warnings.
- [x] 8.2 `stack test` — both suites pass.
- [x] 8.3 `cd web && npm run build && npm run lint` — clean.
- [x] 8.4 Demo runs end to end, exit 0.
- [x] 8.5 Exercise `POST /api/drafts` against a live server: a future range
  succeeds, a past range returns 409 with the freeze-line body.
- [x] 8.6 Update `docs/STATUS.md` and archive this change.
