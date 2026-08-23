## Why

`Assignment` serialises worker and station as bare integers, but neither list endpoint
returns an id: `handleListWorkers` maps it away and `handleListStations` explicitly
discards it (`pure [st | (_, st) <- stations]`). A browser holding a list of assignments
therefore has no way to name the participants.

`web/src/api/calendar.ts` works around this by fetching `GET /api/export` — the entire
database dump — purely to build two id→name maps. Any assignment grid needs the same
lookup, so this is the prerequisite for the `/drafts` detail page (step 7 of item 1 in
`docs/STATUS.md`).

## What Changes

- `GET /api/stations` gains an `id` field on each element. The response element becomes a
  new `StationResp` rather than a bare `Station`, because the domain `Station` record
  deliberately holds no id.
- `GET /api/workers` gains an `id` field on each element (the `WorkerId`, which equals the
  owning `users.id`). `WorkerSummary` and `WorkerSummaryResp` both grow the field.
- `web/src/api/calendar.ts` drops `fetchNameMaps`' dependency on `/api/export` and builds
  its maps from `/api/stations` and `/api/workers?status=all` instead.

## Capabilities

### Modified Capabilities
- `station-rest-names`: the list requirement currently states "No numeric IDs SHALL be
  included in the response". That is reversed for the list endpoint only; every *addressing*
  path stays name-based.
- `worker-list-endpoint`: the `WorkerSummaryResp` shape gains `id`.

## Impact

- **Repo layer** (`src/Repo/Types.hs`, `src/Repo/SQLite.hs`): `WorkerSummary` gains
  `wsId`; `sqlListWorkerSummaries` selects `u.id`.
- **Server** (`server/Server/Json.hs`, `Api.hs`, `Handlers.hs`): new `StationResp`;
  `WorkerSummaryResp` gains `wsrId`; `GET /api/stations` return type changes.
- **Frontend** (`web/src/api/stations.ts`, `workers.ts`, `calendar.ts`): `id` on both
  summary types; `fetchNameMaps` re-sourced.
- **Tests** (`test/ApiSpec.hs`): station list assertions.
- No DB schema change. No CLI change. No RPC change — `rpc/station/list` already returns
  `[(Int, Text)]`.
