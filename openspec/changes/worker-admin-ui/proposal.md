## Why

Workers are now first-class entities (changes 1 and 2), but the React admin UI still has no pages for them — operators must use the CLI to view, deactivate, activate, delete, or rename workers. This third and final foundation change ships the minimal admin UI loop (find worker → manage status → delete/rename) so non-CLI operators can do routine worker lifecycle tasks. It also closes a behavioral asymmetry: `worker delete` is safe-by-default with a `force-delete` companion, but `worker deactivate` commits unconditionally — a UI confirmation modal needs the same safe-then-force protocol.

## What Changes

- Add `WorkersListPage` (route `/workers`): table view, status filter (`active`/`inactive`/`all`) bound to URL query, `[New Worker]` and `[New User (no worker)]` create buttons, per-row Activate/Deactivate/Delete actions.
- Add `WorkerDetailPage` (route `/workers/:name`): identity-only — name (rename), status with Activate/Deactivate buttons, read-only `userId`/`workerId`/`role`, placeholder cards for sections still managed via CLI (employment, preferences, skills, station prefs, cross-training, pairing).
- Add `GET /api/workers?status=active|inactive|all` returning `[WorkerSummaryResp]` (slim shape: name, role, status, isTemp, weekendOnly, seniority).
- **BREAKING**: `worker deactivate` (CLI + REST) becomes safe — succeeds with no commit if zero impact, returns counts and refuses to commit if any pins/drafts/future-calendar entries would be cleared. Add `worker force-deactivate` (CLI) and `PUT /api/workers/:name/deactivate/force` (REST) to commit unconditionally. Mirrors the existing `worker delete` / `worker force-delete` pattern.
- Add `Service.Worker.previewDeactivation` (read-only count) and split the existing deactivation service function into safe and force variants.
- SSE: workers UI subscribes to both `worker` and `user` entity events, since `user rename`, `user create`, and `user force-delete` can affect worker rows but classify under `entityType="user"`.
- Verify `POST /api/users` exposes the `noWorker` flag (added in change 1's CLI); add to REST if missing.

## Capabilities

### New Capabilities
- `worker-admin-pages`: React admin UI — list page (with status filter and create buttons), detail page (identity-only), Deactivate-with-preview flow, and dual-entity SSE subscriptions for staying in sync across user-level mutations.
- `worker-list-endpoint`: `GET /api/workers?status=...` returning slim summaries; the list view's data source.
- `worker-deactivate-safe`: Safe-then-force protocol for deactivation across CLI + REST, mirroring the existing `worker delete` / `worker force-delete` semantics.

### Modified Capabilities
- `worker-deactivate`: requirement changes from "commits unconditionally and returns counts" to "succeeds-or-reports-impact"; add new force verb.

## Impact

- **Frontend** (`web/src/`): new components `WorkersListPage.tsx`, `WorkerDetailPage.tsx`; new `web/src/api/workers.ts`; route registration in `App.tsx`; existing `Sidebar.tsx` link already points to `/workers` (currently 404s).
- **Server** (`server/Server/`): new endpoints in `Api.hs` and `Handlers.hs`; new `WorkerSummaryResp` in `Json.hs`; behavior change in `handleDeactivateWorker`; new `handleForceDeactivateWorker`.
- **CLI** (`cli/`): `worker deactivate` semantics change; add `worker force-deactivate` verb. Update help text.
- **Service layer** (`src/Service/Worker.hs`): split deactivate into preview/safe/force; new `previewDeactivation`.
- **Audit classifier** (`src/Audit/CommandMeta.hs`): classify `worker force-deactivate` as a worker mutation.
- **Repo layer** (`src/Repo/SQLite.hs`): may need a count-only query for the deactivation impact (or reuse existing queries with no commit).
- No DB schema changes. No data migration.
