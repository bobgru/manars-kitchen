## 1. Domain and Repository

- [ ] 1.1 Add `Station` record type to `Domain/Types.hs` with `stationName :: Text`, `stationMinStaff :: Int`, `stationMaxStaff :: Int`
- [ ] 1.2 Change `repoListStations` signature from `IO [(StationId, Text)]` to `IO [(StationId, Station)]` in `Repo/Types.hs`
- [ ] 1.3 Add `repoRenameStation :: StationId -> Text -> IO ()` to `Repo/Types.hs`
- [ ] 1.4 Update `sqlListStations` in `Repo/SQLite.hs` to SELECT name, min_staff, max_staff and return `Station` records
- [ ] 1.5 Implement `sqlRenameStation` in `Repo/SQLite.hs` and wire into `newSQLiteRepo`
- [ ] 1.6 Fix all call sites that destructure `(sid, name)` from `repoListStations` to use `(sid, station)` with `stationName station`

## 2. Service Layer

- [ ] 2.1 Add `StationReferences` type with `strWorkerPrefs :: [(WorkerId, String)]` and `strRequiredSkills :: [(SkillId, String)]`
- [ ] 2.2 Add `checkStationReferences :: Repository -> StationId -> IO StationReferences` that checks worker station preferences (`wcStationPrefs`) and station required skills (`scStationRequires`)
- [ ] 2.3 Add `isStationUnreferenced :: StationReferences -> Bool`
- [ ] 2.4 Add `safeDeleteStation :: Repository -> StationId -> IO (Either StationReferences ())` that checks references and returns Left with details if any exist
- [ ] 2.5 Add `renameStation :: Repository -> StationId -> Text -> IO ()` to `Service/Worker.hs`
- [ ] 2.6 Update `addStation` to accept optional min/max staff (default 1); update `repoCreateStation` signature accordingly

## 3. CLI Commands

- [ ] 3.1 Rename command constructors: `StationAdd` → `StationCreate`, `StationRemove` → `StationDelete`
- [ ] 3.2 Add new command constructors: `StationForceDelete`, `StationRename`, `StationView`
- [ ] 3.3 Change all station command constructors from `Int` ID arguments to `String` name arguments
- [ ] 3.4 Update CLI parser: `station add` → `station create` (with optional positional min/max staff defaulting to 1), `station remove` → `station delete`, add `station rename <old> <new>`, `station view <name>`, `station force-delete <name>`
- [ ] 3.5 Update CLI executor in `App.hs`:
  - `StationCreate`: resolve name, pass optional min/max staff to `addStation`
  - `StationDelete`: resolve name to ID, call `safeDeleteStation`, print references if blocked
  - `StationForceDelete`: check references; for each worker with station in prefs, load pref list, filter out station, call `WorkerSetPrefs`; for each required skill, call `StationRemoveRequiredSkill`; then call `StationDelete`
  - `StationRename`: resolve old name to ID, call `renameStation`
  - `StationView`: resolve name to ID, display name, min/max staff, hours/closures/multi-station hours, required skills, worker preferences
- [ ] 3.6 Update `Resolve.hs` `commandEntityMap` for renamed verbs and new commands (`station create`, `station delete`, `station force-delete`, `station rename`, `station view`)

## 4. Audit Log

- [ ] 4.1 Update `classifyStation` in `Audit/CommandMeta.hs` for new verb names (create/delete/force-delete/rename/view)
- [ ] 4.2 Update demo script `demo/restaurant-setup.txt`: rename `station add` to `station create`

## 5. REST API

- [ ] 5.1 Update `CreateStationReq` in `Server/Json.hs`: drop `cstrId`, change `cstrName` from `String` to `Text`, add `cstrMinStaff` and `cstrMaxStaff` as `Int` with parser-level defaults of 1 (`.:? "minStaff" .!= 1`)
- [ ] 5.2 Add `RenameStationReq` JSON type in `Server/Json.hs`
- [ ] 5.3 Add `Station` JSON instance (ToJSON) for the list endpoint response (name, minStaff, maxStaff)
- [ ] 5.4 Add `StationReferencesResp` JSON type mirroring `SkillReferencesResp` pattern
- [ ] 5.5 Update station route types in `Server/Api.hs`: change `Capture "id" Int` to `Capture "name" Text` on all station routes; add rename (`PUT` with `RenameStationReq`) and force-delete (`DELETE .../force`) routes
- [ ] 5.6 Add `resolveStationName :: Repository -> Text -> Handler StationId` in `Handlers.hs`
- [ ] 5.7 Update `lookupStationName` to return `Text` and destructure `Station` records
- [ ] 5.8 Update `handleListStations` to return `[Station]` (name, minStaff, maxStaff — no IDs)
- [ ] 5.9 Update `handleCreateStation` to use new `CreateStationReq` (name, optional minStaff/maxStaff)
- [ ] 5.10 Update `handleDeleteStation` to resolve by name and use `safeDeleteStation`; return 409 with `StationReferencesResp` if blocked
- [ ] 5.11 Add `handleForceDeleteStation` that resolves name then calls `executeCommandText` with `"station force-delete <name>"`
- [ ] 5.12 Add `handleRenameStation` that resolves name, calls `SW.renameStation`, logs via `logRest`
- [ ] 5.13 Update `handleSetStationHours` and `handleSetStationClosure` to resolve by name
- [ ] 5.14 Wire all updated/new handlers into the server in `Server/Api.hs`

## 6. React Admin UI

- [ ] 6.1 Create `web/src/api/stations.ts` with `fetchStations`, `createStation`, `deleteStation`, `forceDeleteStation`, `renameStation`
- [ ] 6.2 Create `web/src/components/StationsListPage.tsx` with station table (Name linked to detail, Min Staff, Max Staff, Delete column), create form (name only), safe/force-delete modal following Skill pattern
- [ ] 6.3 Create `web/src/components/StationDetailPage.tsx` — minimal: name (editable inline with save/rename), min/max staff (read-only)
- [ ] 6.4 Add `/stations` and `/stations/:name` routes to `AppShell.tsx`
- [ ] 6.5 Add "Stations" link to `Sidebar.tsx`
- [ ] 6.6 Use `useEntityEvents("station", loadData)` on both pages for auto-reload

## 7. CLI Display

- [ ] 7.1 Add `displayStationView` to `CLI/Display.hs` showing: name (with ID), min/max staff, hours/closures/multi-station hours (reusing `showStationHoursNote` formatting), required skills, worker preferences; "Hours: all" if no hours configured

## 8. Verify

- [ ] 8.1 Build and fix all compiler warnings
- [ ] 8.2 Run tests and fix failures
- [ ] 8.3 Run demo replay and verify it completes successfully
- [ ] 8.4 Test station CRUD through the web UI in browser
