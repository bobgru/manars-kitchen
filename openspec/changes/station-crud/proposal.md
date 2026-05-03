## Why

Station is the only entity with a web-accessible REST API that still uses numeric IDs in its routes and lacks an admin UI page. Skill has been fully migrated to name-based routes with a list+detail React UI. Bringing Station to parity establishes the pattern for the remaining entities and gives the admin a usable station management page.

## What Changes

- Introduce a `Station` domain type (`stationName`, `stationMinStaff`, `stationMaxStaff`) replacing the bare `(StationId, Text)` tuple pattern.
- Rename CLI verbs for consistency: `station add` → `station create`, `station remove` → `station delete`.
- Add missing CLI commands: `station rename`, `station view`, `station force-delete`.
- Switch all station CLI commands from numeric ID arguments to name arguments.
- Switch all station REST endpoints from `/:id` to `/:name`.
- Add REST endpoints for rename and force-delete.
- Change `GET /api/stations` to return `[Station]` (name, minStaff, maxStaff) with no IDs.
- Drop the `id` field from `CreateStationReq`; switch `name` field from `String` to `Text`.
- Build a `StationsListPage` and `StationDetailPage` in the React admin UI following the Skill page pattern.
- Update audit log command strings to use the new verb names.

## Capabilities

### New Capabilities
- `station-domain-type`: Introduce a Station record type in the domain layer, replacing bare tuples in the repository interface
- `station-cli-parity`: Rename station CLI verbs and add rename/view/force-delete commands to match Skill
- `station-rest-names`: Switch all station REST endpoints from ID-based to name-based routes, add rename and force-delete endpoints
- `station-admin-pages`: React list and detail pages for station management following the Skill UI pattern

### Modified Capabilities
- `name-based-entity-resolution`: Station commands now use create/delete/force-delete/rename/view verbs instead of add/remove

## Impact

- **Domain**: New `Station` type in `Domain/Station.hs` or `Domain/Types.hs`
- **Repository**: `repoListStations` signature changes from `IO [(StationId, Text)]` to `IO [(StationId, Station)]`; add `repoRenameStation`
- **CLI**: Command parser and executor updated for renamed/new commands; all station commands take names not IDs
- **REST API**: All station route types change; handler signatures change; JSON request/response types change
- **React**: New components `StationsListPage`, `StationDetailPage`, `api/stations.ts`; sidebar and router updates
- **Audit**: CommandMeta classifier updated for new verb names; demo/replay scripts updated
- **Breaking**: REST API routes change shape (`:id` → `:name`); no external consumers exist so this is safe
