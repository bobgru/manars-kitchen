## Context

`Domain.Types.Station` is `{stationName, stationMinStaff, stationMaxStaff}` — no id, by
design: the repo hands out `[(StationId, Station)]` and the id belongs to the storage
layer, not the algebraic core. `handleListStations` currently drops the left component.

Workers are different: `WorkerId` *is* `users.id` (`Auth.Types.userIdToWorkerId`), and
`WorkerProfileResp` already exposes both `userId` and `workerId`. Only the slim list row
omits it.

## Decisions

### Decision: a `StationResp` wrapper, not an id field on `Station`

`GET /api/stations` returns `[StationResp]` where

```haskell
data StationResp = StationResp
    { stnId       :: !Int
    , stnName     :: !Text
    , stnMinStaff :: !Int
    , stnMaxStaff :: !Int
    }
```

**Alternatives considered:**

- *Add `stationId` to `Domain.Types.Station`.* Rejected: it would put a storage identifier
  into the domain record that the scheduler, the optimizer and every `Arbitrary` instance
  construct, and `Station` is compared with `Eq`/`Ord` in scheduling code where two
  stations differing only by id would stop being equal.
- *Return `[(StationId, Station)]` and let aeson emit a 2-tuple array.* Rejected: the
  payload becomes `[[1, {...}]]`, which is awkward to consume and inconsistent with every
  other REST response in this codebase.
- *Leave `Station`'s `ToJSON` alone and add a separate `GET /api/stations/ids`.* Rejected:
  two round-trips and two sources of truth for the same list.

The existing `ToJSON`/`FromJSON Station` instances stay as they are — they are also used by
`Domain.Scheduler`'s result serialisation and by import/export, neither of which wants an
id.

### Decision: worker id comes from `users.id`, added at the repo layer

`sqlListWorkerSummaries` already selects from `users u`; adding `u.id` to the projection is
a one-column change. `WorkerSummary` gains `wsId :: !WorkerId` so the mapping to
`WorkerSummaryResp` needs no second query.

### Decision: `fetchNameMaps` calls the two list endpoints

The calendar page needs *all* workers, including inactive ones, because past calendar
assignments can reference a worker who has since been deactivated — hence
`?status=all`. Two small requests replace one whole-database dump.

## Risks

`GET /api/workers` requires admin. `fetchNameMaps` was already reading `/api/export`,
which also requires admin, so no page loses access that it had.
