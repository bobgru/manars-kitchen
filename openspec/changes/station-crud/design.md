## Context

Skill has been fully migrated: domain type (`Skill` record), name-based REST routes, safe/force delete, rename, and a React admin UI (list + detail pages). Station lags behind — it uses a bare `(StationId, Text)` tuple in the repo layer, REST routes use numeric IDs, CLI verbs don't match Skill's naming, and there's no React UI.

The existing `resolveSkillName` handler helper and `lookupStationName` utility in `Handlers.hs` show the resolution pattern. Station already has name resolution in the CLI layer (`Resolve.hs` with `EStation`).

## Goals / Non-Goals

**Goals:**
- Introduce a `Station` domain type alongside `Skill` as the second fully-migrated entity
- Name-based REST API routes for all station endpoints
- CLI verb parity with Skill (create/delete/force-delete/rename/view/list)
- React admin pages following the Skill UI pattern (list + detail)
- All station CLI commands accept names instead of numeric IDs

**Non-Goals:**
- Building React UI for station configuration (hours, closures, required skills) — that's a follow-up
- Changing how station configuration is stored internally (SkillContext maps are untouched)
- Migrating Worker, AbsenceType, or Absence in this change

## Decisions

### D1: Station domain type location

Put `Station` in `Domain/Types.hs` alongside `StationId`, not in a separate `Domain/Station.hs` file.

**Rationale:** `Skill` got its own module because it contains substantial logic (implication graphs, qualification checks, staffing queries). `Station` is a pure data record with no domain logic — it belongs with the other simple types. If station-specific logic grows later, it can be extracted then.

### D2: Repository change — widen repoListStations

Change `repoListStations :: IO [(StationId, Text)]` to `IO [(StationId, Station)]`. The SQL query adds `min_staff, max_staff` to the SELECT. All call sites that destructure `(sid, name)` change to `(sid, station)` and use `stationName station`.

**Alternative considered:** Add a separate `repoGetStation :: StationId -> IO (Maybe Station)`. Rejected because the list is small and always fully loaded — a separate lookup would be an extra query for no benefit.

### D3: resolveStationName handler helper

Add `resolveStationName :: Repository -> Text -> Handler StationId` in `Handlers.hs`, mirroring `resolveSkillName`. Case-insensitive lookup. All station handlers that currently take `Int` switch to taking `Text` and calling this resolver.

Also update `lookupStationName` to return `Text` instead of `String`, since it now destructures `Station` records.

### D4: Safe delete with reference checking

`DELETE /api/stations/:name` checks for references before deleting:
- Worker station preferences (`wcStationPrefs` in WorkerContext)
- Station required skills (`scStationRequires` in SkillContext)
- Assignments in active schedules

If references exist, return 409 with a structured error listing them (same pattern as Skill). `DELETE /api/stations/:name/force` removes all references first, then deletes.

The CLI `station delete` calls safe delete; `station force-delete` calls force delete.

### D5: CLI verb rename — audit log compatibility

`station add` → `station create`, `station remove` → `station delete`. The `CommandMeta` classifier in `Audit/CommandMeta.hs` updates to classify the new verb names. Old verb names in existing audit log entries won't match the new classifier — this is fine because replay always wipes and replays from scratch, so old entries are never re-parsed.

Demo scripts and any hardcoded replay files must be updated to use the new verbs.

### D6: React page pattern — follow Skill exactly

- `StationsListPage.tsx`: table with Name/Min Staff/Max Staff columns, create form (name only), delete buttons with safe/force-delete modal
- `StationDetailPage.tsx`: view station attributes, inline rename with save button
- `api/stations.ts`: API client module with `fetchStations`, `createStation`, `deleteStation`, `forceDeleteStation`, `renameStation`
- Routes: `/stations` for list, `/stations/:name` for detail
- Sidebar: "Stations" link below "Skills"

### D7: String-to-Text cleanup in station paths

`CreateStationReq` drops `cstrId` and changes `cstrName` from `String` to `Text`. `SetStationHoursReq` and `SetStationClosureReq` remain unchanged (they have no string fields). Handler audit-log calls switch from `String` concatenation to `Text`-based formatting where practical.

## Risks / Trade-offs

- **Repo signature change is cross-cutting** — every caller of `repoListStations` needs updating. Mitigated by the fact that there are few call sites (handlers, CLI app, service layer) and the compiler catches all of them.
- **CLI verb rename is a breaking change** — anyone with muscle memory for `station add` will need to adjust. Mitigated by the fact that this is a personal project with one admin user, and the rename brings consistency.
- **Safe delete reference checking requires loading full contexts** — loading WorkerContext and SkillContext to check station references is more expensive than a targeted query. Acceptable because stations are few and deletion is rare. Can be optimized with targeted queries later if needed.
