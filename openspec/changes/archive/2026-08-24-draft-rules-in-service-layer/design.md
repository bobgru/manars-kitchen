## Context

`Service.Draft` is a thin wrapper over the draft repository fields. Everything
that makes a draft *safe* — the freeze-line refusal, the what-if cleanup, the
auto-refreeze — sits above it in `src/CLI/App.hs`, in the same case expression
that prints the output. REST reaches the same service functions without passing
through any of it.

Two constraints shape the design:

1. **Unfreezes are session state, not stored state.** `asUnfreezes` is an
   `IORef (Set (Day, Day))` in `AppState`, created per CLI process. `docs/STATUS.md`
   records the decision that unfreeze stays CLI-only, so this change must not
   invent a `unfreezes` table.
2. **The freeze line is computed, never stored.** `computeFreezeLine` reads the
   clock. Anything that consults it is time-dependent by construction.

## Decisions

### The unfreeze set is an argument, not a lookup

`createDraft` takes a `CreateDraftOpts` record:

```haskell
data CreateDraftOpts = CreateDraftOpts
    { cdoForce     :: !Bool
    , cdoUnfreezes :: !(Set.Set (Day, Day))
    }

defaultCreateDraftOpts :: CreateDraftOpts   -- force off, no unfreezes
```

The alternative — give the service a way to read the unfreezes — requires either
persisting them or handing the service an `IORef`, which makes a service function
depend on a CLI-shaped mutable cell. Passing the set in keeps the service pure
with respect to session state, and makes the REST behaviour fall out for free:
REST has no unfreezes, so `defaultCreateDraftOpts` refuses every frozen range.
That is the decided behaviour, not an accident of the encoding.

A record rather than two positional arguments because
`createDraft repo True someSet from to` is unreadable, and step 3 removes the
overlap check from the same function — the record absorbs that without another
signature churn.

### The refusal is structured, and the CLI is the only thing that formats it

```haskell
data FrozenRange = FrozenRange
    { frFreezeLine :: !Day
    , frFrom       :: !Day
    , frTo         :: !Day
    }

data CreateDraftError
    = DraftOverlapsExisting
    | DraftCoversFrozenDates !FrozenRange
```

`Either String Int` cannot survive this: the CLI needs the frozen sub-range to
print `calendar unfreeze <from> <to>` and the server needs the same three dates as
JSON fields. Formatting a string in the service and re-parsing it in two clients
is how the two surfaces drifted in the first place.

The 409 body is
`{"error": ..., "freezeLine": ..., "frozenFrom": ..., "frozenTo": ...}` — an
`error` key so a client that only reads `error` (every existing one) still shows
something useful, plus the three dates for a client that wants to offer an
unfreeze affordance later.

### Auto-refreeze is reported, not performed

`commitDraft` cannot clear the CLI's unfreezes: it has no reference to the
`IORef`, and giving it one recreates the coupling this change removes. So it
returns what it knows:

```haskell
data CommitOutcome = CommitOutcome { coCoveredFrozenDates :: !Bool }
```

The CLI clears and prints when the flag is `True` **and** it has unfreezes to
clear — the same condition as today, so `freeze-line`'s "Commit draft with only
future dates" scenario still shows nothing. The rule that *decides* whether the
range was historical now lives in the service; only the effect on session state
stays with the session.

Note this is honest about a limit: an admin who unfreezes in the CLI and then
commits over REST does not get their unfreezes cleared, because that REST process
never had them. Nothing can fix that without persisting unfreezes, which is out
of scope.

### Hint cleanup moves down, and widens

The CLI deletes `repoDeleteHintSession (asSessionId st) did` — its own session's
row. A second admin with a saved session for the same draft keeps a row pointing
at a deleted draft, which `draft open` can never reach again because the draft is
gone.

The service gets `repoDeleteDraftHintSessions :: Int -> IO ()`
(`DELETE FROM hint_sessions WHERE draft_id = ?`) and calls it from both
`commitDraft` and `discardDraft`. The CLI keeps clearing its *in-memory*
`asHintSession` when it points at the committed draft, because that is session
state and the service cannot see it.

### `Nothing` means active workers, and that is a behaviour change

`generateDraft` takes `Maybe (Set.Set WorkerId)`. `Nothing` resolves through

```haskell
activeWorkerIds :: Repository -> IO (Set.Set WorkerId)
activeWorkerIds repo = Set.fromList <$> repoLoadWorkerIdsByStatus repo WSActive
```

The CLI passes `Nothing` and so drops its own `[userIdToWorkerId (userId u) | u <- users]`
over `repoListUsers`, which included `WSInactive` workers and `WSNone` accounts.
Every account the demo creates is `WSActive` (`sqlCreateUser` sets it, and the
bootstrap admin is registered with `noWorker = False`), so the demo is unaffected;
a database with a deactivated worker changes, correctly.

The alternative — keep the CLI enumerating and only default on the server — was
rejected because it leaves two definitions of the default worker set, which is the
class of divergence this whole step exists to close.

### Where the freeze check sits relative to the overlap check

Freeze first. The CLI checks freeze before ever calling `createDraft`, so
preserving the order preserves the message a user sees when a range is both frozen
and overlapping. Step 3 deletes the overlap arm, at which point the order stops
mattering.

## Consequences for the tests

`createDraft` now reads the clock, so a fixture on a hardcoded 2026 date is
frozen and refused. Two different answers, chosen per suite:

- **Service-level suites** (`DraftSpec`, `DraftValidationSpec`, `HintE2ESpec`)
  keep their fixture dates and pass `defaultCreateDraftOpts { cdoForce = True }`.
  Forcing is what an operator would do to work on history, so the fixture reads as
  what it is.
- **`ApiSpec`** cannot force: REST has no force. Its draft tests move onto dates
  computed from the current date, which is also what a browser would send. One new
  test asserts the 409 for a range in the past — the behaviour this change exists
  to add.

## Open questions

None. The one thing deliberately left unresolved is the CLI-unfreeze /
REST-commit gap above, which is a consequence of the recorded decision that
unfreeze stays CLI-only.
