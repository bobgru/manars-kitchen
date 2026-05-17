## 1. Service-layer deactivation split

- [ ] 1.1 In `src/Service/Worker.hs`, add `previewDeactivation :: Repository -> WorkerId -> IO DeactivateResult` that counts pins, draft entries, and future calendar entries for the worker without modifying state
- [ ] 1.2 Rename existing unconditional deactivation function to `forceDeactivateWorker` (keep its current behavior — commits and returns counts)
- [ ] 1.3 Add `safeDeactivateWorker :: Repository -> WorkerId -> Day -> IO (Either DeactivateResult DeactivateResult)` returning `Right counts` (all zero, committed) or `Left counts` (nonzero, not committed)
- [ ] 1.4 Audit existing call sites of the old function and switch them to `forceDeactivateWorker` to preserve current behavior outside the new safe-then-force flow

## 2. CLI: worker deactivate semantics + force-deactivate verb

- [ ] 2.1 Update `worker deactivate <name>` handler to call `safeDeactivateWorker`; on `Left counts`, print impact and instruct user to run `worker force-deactivate`
- [ ] 2.2 Add `worker force-deactivate <name>` verb wired to `forceDeactivateWorker`
- [ ] 2.3 Update `cli` help text and any README references for `worker deactivate`
- [ ] 2.4 Update `src/Audit/CommandMeta.hs` `classifyWorker` to recognize `"force-deactivate"` as a worker mutation

## 3. REST: deactivate semantics + force endpoint

- [ ] 3.1 Change `PUT /api/workers/:name/deactivate` handler in `server/Server/Handlers.hs`: call `safeDeactivateWorker`; return 204 on `Right`, 409 with `DeactivateResultResp` body on `Left`
- [ ] 3.2 Add route `PUT /api/workers/:name/deactivate/force` in `server/Server/Api.hs` and `handleForceDeactivateWorker` in `Handlers.hs` that calls `forceDeactivateWorker` and returns 200 with counts
- [ ] 3.3 Audit log line for `force-deactivate` calls (CLI string `worker force-deactivate <name>`)

## 4. REST: workers list endpoint

- [ ] 4.1 Add route `"api" :> "workers" :> QueryParam "status" Text :> Get '[JSON] [WorkerSummaryResp]` in `server/Server/Api.hs`
- [ ] 4.2 Add `WorkerSummaryResp` record + `ToJSON`/`FromJSON` in `server/Server/Json.hs` with fields name, role, status, isTemp, weekendOnly, seniority
- [ ] 4.3 Implement `handleListWorkers :: Repository -> User -> Maybe Text -> Handler [WorkerSummaryResp]` in `server/Server/Handlers.hs`: validate status (`active`/`inactive`/`all`, default `active`), reject invalid with 400, exclude `worker_status='none'` always, require admin
- [ ] 4.4 Add `repoListWorkerSummaries` (or similar) in `src/Repo/SQLite.hs` joining users + the relevant `worker_*` config tables for the summary fields

## 5. REST: confirm POST /api/users supports noWorker flag

- [ ] 5.1 Read `server/Server/Json.hs` `CreateUserReq` to confirm whether `noWorker` is parsed; if missing, add it (optional, default false)
- [ ] 5.2 Read `handleCreateUser` to confirm it threads `noWorker` to the service layer; if missing, thread it through
- [ ] 5.3 Add or update tests covering the `noWorker: true` path returning a user with `worker_status='none'`

## 6. Frontend: api/workers.ts client module

- [ ] 6.1 Create `web/src/api/workers.ts` with `WorkerSummary`, `WorkerProfile`, `DeactivationImpact`, `WorkerReferences` types matching server JSON
- [ ] 6.2 Implement `fetchWorkers(status)`, `fetchWorkerProfile(name)`, `activateWorker`, `deleteWorker`, `forceDeleteWorker` using `apiFetch`
- [ ] 6.3 Implement `deactivateWorker(name)` returning `{ok: true}` on 204 / `{ok: false, impact}` on 409
- [ ] 6.4 Implement `forceDeactivateWorker(name)` returning the impact counts from 200 OK
- [ ] 6.5 Implement `renameWorker(name, newName)` (resolves user id from name then calls existing `PUT /api/users/:id`); or a single helper that accepts the worker name and dispatches
- [ ] 6.6 Implement `createUser({username, password, role, noWorker?})` calling `POST /api/users`

## 7. Frontend: WorkersListPage

- [ ] 7.1 Create `web/src/components/WorkersListPage.tsx`
- [ ] 7.2 Read `?status=` from `useSearchParams` (default `active`); render a filter control with three options (Active/Inactive/All); changing the filter updates the URL
- [ ] 7.3 Fetch via `fetchWorkers(status)` on mount and on filter change
- [ ] 7.4 Render table with columns: Name (link to `/workers/:name`), Role, Status, Temp, Weekend-only, Seniority
- [ ] 7.5 Render `[New Worker]` and `[New User (no worker)]` buttons with shared inline form (username, password, role); submit via `createUser`
- [ ] 7.6 Per-row action buttons by status: active → `[Deactivate]` `[Delete]`; inactive → `[Activate]` `[Delete]`
- [ ] 7.7 Implement deactivate-with-preview flow: call `deactivateWorker`; on `{ok: true}` toast + reload; on `{ok: false, impact}` show modal with counts and `[Cancel]` `[Deactivate Anyway]` (calls `forceDeactivateWorker`)
- [ ] 7.8 Implement delete flow: call `deleteWorker`; on `{ok: false, references}` show modal with `[Cancel]` `[Force Delete]` (calls `forceDeleteWorker`)
- [ ] 7.9 Implement activate as single-click (no confirmation)
- [ ] 7.10 Subscribe to SSE: `useEntityEvents("worker", load)` AND `useEntityEvents("user", load)`
- [ ] 7.11 Loading and error states

## 8. Frontend: WorkerDetailPage

- [ ] 8.1 Create `web/src/components/WorkerDetailPage.tsx`
- [ ] 8.2 Fetch worker profile via `fetchWorkerProfile(decodedName)` on mount
- [ ] 8.3 Render identity section: editable name with Save button; status with `[Activate]` or `[Deactivate]` button; read-only role, userId, workerId
- [ ] 8.4 Implement rename (calls `renameWorker`, then navigates to new URL)
- [ ] 8.5 Reuse deactivate-with-preview and activate behavior from list page (factor into shared helper if natural)
- [ ] 8.6 Render placeholder cards for the 18 deferred fields (Skills, Employment, Preferences, Station Prefs, Cross-training, Pairing) with read-only values and "managed via CLI for now" label
- [ ] 8.7 Subscribe to SSE: `worker` and `user`
- [ ] 8.8 Worker-not-found state with link back to list

## 9. Frontend: route registration

- [ ] 9.1 Register `/workers` and `/workers/:name` routes in `web/src/App.tsx`
- [ ] 9.2 Verify sidebar "Workers" link works (already present in `Sidebar.tsx`)

## 10. Verification + cleanup

- [ ] 10.1 `stack clean && stack build && stack test` — fix all build + test warnings before finishing (per project convention)
- [ ] 10.2 Run dev server; manually exercise: navigate `/workers`, switch filters, create a worker, create a non-worker user, deactivate (zero-impact path), deactivate (nonzero-impact preview path), activate, delete (no refs path), delete (refs path), rename via detail page
- [ ] 10.3 Cross-session SSE test: in two browser tabs, mutate from CLI/REST and confirm both pages re-fetch (covering `user rename`, `user force-delete`, `worker deactivate`)
- [ ] 10.4 Confirm the demo command still works end-to-end (per project convention)
- [ ] 10.5 Update `CHANGELOG.md` with the breaking CLI change in `worker deactivate` and the new `worker force-deactivate` verb
