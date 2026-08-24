## 1. Repository and storage

- [x] 1.1 `src/Repo/Types.hs`: delete `repoSaveSchedule`, `repoLoadSchedule`,
  `repoListSchedules`, `repoDeleteSchedule`.
- [x] 1.2 `src/Repo/SQLite.hs`: delete the four wirings and the `sqlSaveSchedule`,
  `sqlLoadSchedule`, `sqlListSchedules`, `sqlDeleteSchedule` implementations.
- [x] 1.3 `src/Repo/SQLite.hs`: drop `DELETE FROM assignments` / `DELETE FROM schedules`
  from `sqlWipeAll` and `DELETE FROM assignments` from `sqlCascadeWorkerSchedule` —
  they would fail with *no such table* once 1.4 lands.
- [x] 1.4 `src/Repo/Schema.hs`: delete the `schedules` and `assignments`
  `CREATE TABLE` statements. No `DROP TABLE`.

## 2. Service layer

- [x] 2.1 Delete `src/Service/Schedule.hs` and its `manars-kitchen.cabal` entry.
- [x] 2.2 `src/Service/Worker.hs`: drop `wrSchedule` from `WorkerReferences`, the
  named-schedule scan in `checkWorkerReferences`, and its use in
  `scheduleRefsNonEmpty`.
- [x] 2.3 `src/CLI/Display.hs`: drop the `schedule assignments` field from the
  worker-references display.
- [x] 2.4 `server/Server/Handlers.hs`: drop the `schedule` count from
  `WorkerReferencesResp`.

## 3. Export / import

- [x] 3.1 `src/Export/JSON.hs`: delete `expSchedules`, the `schedules` key in
  `ToJSON`/`FromJSON`, the gather block and `importSchedule`.
- [x] 3.2 `src/Export/JSON.hs`: `gatherExport :: Repository -> IO ExportData`
  (drop the `Maybe Text`); update the four call sites.

## 4. CLI

- [x] 4.1 `src/CLI/Commands.hs`: delete the ten `Schedule*` constructors,
  `CmdAssign`, `CmdUnassign`, `CmdExportSchedule`, `CalendarDoCommit` and their
  parse arms.
- [x] 4.2 `src/CLI/App.hs`: delete the matching `handleCommand` arms, the
  `isMutating` arms, the `schedule` help-group rows, the `export <schedule> <file>`
  help row, the `calendar commit` help row and the `schedule` group description.
- [x] 4.3 `src/CLI/Resolve.hs`: delete the `["assign"]` and `["unassign"]` entries
  from `commandEntityMap`.
- [x] 4.4 `src/Audit/CommandMeta.hs`: delete `classifySchedule`, `classifyAssign`,
  `classifyUnassign`, their `classify` arms, and the `calendar commit` name
  placeholder in `renderParts`. Keep `etSchedule` — it is the entity type for
  `help`, `quit`, `audit`, `replay`, `demo`, `use` and `context`.
- [x] 4.5 `cli/CLI/RpcClient.hs`: delete the dispatch arms for every removed
  constructor.

## 5. Server

- [x] 5.1 `server/Server/Api.hs`: delete the three `api/schedules` endpoints.
- [x] 5.2 `server/Server/Handlers.hs`: delete `handleListSchedules`,
  `handleGetSchedule`, `handleDeleteSchedule` and their entries in the server
  record.
- [x] 5.3 `server/Server/Rpc.hs`: delete `rpcListSchedules`, `rpcGetSchedule`,
  `rpcDeleteSchedule`, their routes and any now-unused request types.

## 6. Frontend

- [x] 6.1 `web/src/components/Sidebar.tsx`: `/schedules` → `/drafts`, "Schedules" →
  "Drafts".

## 7. Demo and fixtures

- [x] 7.1 `demo/restaurant-setup.txt`: rewrite the week-1 section onto a draft and
  renumber the six later draft ids from 1–6 to 2–7.
- [x] 7.2 Regenerate `export.json` and `demo-export.json`.

## 8. Tests

- [x] 8.1 `test/ApiSpec.hs`: delete the `/api/schedules` client functions and the
  two tests.
- [x] 8.2 `test/AuditSpec.hs`: delete the `schedule create` / `schedule list`
  classification tests, the `schedule`/`assign`/`unassign` consistency cases, and
  fix the `calendar commit` case.
- [x] 8.3 `test/EventStreamSpec.hs`: replace the `calendar commit` and `assign`
  fixtures.

## 9. Specs

- [x] 9.1 Remove `assign-name-args` and `compact-schedule-display`.
- [x] 9.2 Apply the `calendar-cli`, `command-classifier`, `demo-auto-export`,
  `endpoint-authorization`, `name-based-entity-resolution`, `readme-cli-features`,
  `two-level-help`, `worker-deactivate`, `worker-delete` deltas.
- [x] 9.3 `README.md`: drop `schedule view-compact` and any other removed command.

## 10. Verification

- [x] 10.1 `stack clean && stack build --test` with zero warnings.
- [x] 10.2 `stack test` — integration and unit suites pass.
- [x] 10.3 `cd web && npm run build && npm run lint` — clean.
- [x] 10.4 Demo runs end to end, exit 0; review the regenerated `demo-export.json`
  diff and confirm the only changes are the dropped `schedules` key and the new
  week-1 calendar assignments.
- [x] 10.5 Confirm a fresh database has no `schedules`/`assignments` tables and
  that `demo` and `worker force-delete` still work against it.
- [x] 10.6 Update `docs/STATUS.md` and archive this change.
