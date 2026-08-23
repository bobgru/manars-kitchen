## 1. Worker summary gains an id

- [x] 1.1 In `src/Repo/Types.hs`, add `wsId :: !WorkerId` as the first field of `WorkerSummary`
- [x] 1.2 In `src/Repo/SQLite.hs`, add `u.id` to `sqlListWorkerSummaries`' projection and widen the row tuple
- [x] 1.3 In `server/Server/Json.hs`, add `wsrId :: !Int` to `WorkerSummaryResp` and to its `ToJSON`/`FromJSON` instances as `"id"`
- [x] 1.4 In `server/Server/Handlers.hs`, thread the id through `toSummaryResp`

## 2. Station list gains an id

- [x] 2.1 In `server/Server/Json.hs`, add `StationResp` with `stnId`/`stnName`/`stnMinStaff`/`stnMaxStaff` plus `ToJSON`/`FromJSON`, and export it
- [x] 2.2 In `server/Server/Api.hs`, change the stations list endpoint to `Get '[JSON] [StationResp]`
- [x] 2.3 In `server/Server/Handlers.hs`, rewrite `handleListStations` to keep the `StationId`

## 3. Frontend

- [x] 3.1 `web/src/api/stations.ts`: add `id: number` to `StationInfo`
- [x] 3.2 `web/src/api/workers.ts`: add `id: number` to `WorkerSummary`
- [x] 3.3 `web/src/api/calendar.ts`: rewrite `fetchNameMaps` to use `fetchStations()` and `fetchWorkers("all")`; delete the `ExportResp` interface and update the `NameMaps` doc comment
- [x] 3.4 Confirm no other component depended on the `/api/export` call

## 4. Tests and verification

- [x] 4.1 `test/ApiSpec.hs`: update the Servant client for the stations list endpoint and any assertion that constructs an expected `Station` list
- [x] 4.2 Add a spec asserting `GET /api/stations` includes the created station's id, and one asserting `GET /api/workers` includes an id
- [x] 4.3 `stack clean && stack build --test` clean, `stack test` green
- [x] 4.4 `cd web && npm run build && npm run lint` clean
- [x] 4.5 Demo runs end to end
