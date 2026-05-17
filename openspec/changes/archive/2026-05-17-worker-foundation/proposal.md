## Why

Worker is the only major entity in the system without a CRUD surface, view command, or admin UI page. Workers are not first-class records — they exist implicitly as users with a non-null `worker_id`. There is also no way to take a worker out of active scheduling without deleting their configuration; if a worker leaves on good terms and is later rehired, their skills, preferences, and employment status all have to be re-entered.

This change reorganizes the user/worker relationship around a single status column on `users`, eliminates the separate `worker_id` allocation, and adds the verbs needed to view, rename, deactivate/activate, and delete workers. It is the first of three changes; subsequent changes will switch the existing 30+ `worker <verb> <wid>` commands to name-based addressing and add a React admin UI.

The system has not been deployed; there is no production data to migrate. The database can be dropped and recreated.

## What Changes

- **BREAKING (schema, no data migration):** Drop `users.worker_id`. Add `users.worker_status TEXT NOT NULL DEFAULT 'active' CHECK (worker_status IN ('none','active','inactive'))`. Add `users.deactivated_at TEXT` (ISO date, set when status transitions to `inactive`). The schema is rebuilt from scratch; no migration of existing rows.
- `WorkerId` and `UserId` collapse at the value level: a worker's `WorkerId` equals the integer of their `UserId`. The Haskell newtypes `WorkerId` and `UserId` remain distinct; conversion goes through a single helper `userIdToWorkerId :: UserId -> WorkerId`.
- All `worker_*` tables get a real foreign key: `worker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT`.
- `user create <name> <pass> <role>` no longer allocates `worker_id`. New `--no-worker` flag sets `worker_status = 'none'`. Default behavior creates a worker (`worker_status = 'active'`).
- New CLI: `user rename <old> <new>`. Worker name = username, so this is the only rename verb.
- New CLI: `worker view <name>`. Shows status, employment, hours, skills, prefs, pairings, seniority, cross-training. Works for both active and inactive workers.
- New CLI: `worker deactivate <name>`. Flips status to `inactive`, sets `deactivated_at` to today, removes the worker from pinned assignments, open drafts, and calendar assignments dated today or later. Configuration tables (skills, prefs, employment) are preserved. Past calendar/named-schedule assignments are preserved.
- New CLI: `worker activate <name>`. Flips status to `active`, clears `deactivated_at`. Configuration becomes effective again immediately.
- New CLI: `worker delete <name>`. Permanently removes worker concept (sets `worker_status = 'none'`) only if the worker has no references anywhere. Distinguishes configuration refs from schedule/history refs in the error message.
- New CLI: `worker force-delete <name>`. Cascades: clears all `worker_*` config rows and all worker-keyed schedule/history rows, then sets `worker_status = 'none'`. User account remains.
- New CLI: `user delete <id>` becomes safe. Blocks if user has `worker_status` ∈ {`active`, `inactive`}; the operator must use `worker delete` (or `worker force-delete`) first.
- New CLI: `user force-delete <id>`. Cascade everything (worker refs + user row).
- Scheduler and `WorkerContext` loaders SHALL filter to `worker_status = 'active'`. Inactive workers are never auto-assigned and never count toward `WorkerContext`.
- REST: add `GET /api/workers/:name`, `PUT /api/workers/:name/deactivate`, `PUT /api/workers/:name/activate`, `DELETE /api/workers/:name` (safe), `DELETE /api/workers/:name/force`, `PUT /api/users/:id/rename`, `DELETE /api/users/:id/force`. Extend `CreateUserReq` with optional `noWorker: bool` defaulting to false.
- Audit log: classify the new verbs.
- **Out of scope** (deferred): renaming the existing `worker grant-skill <wid>`, `worker set-hours <wid>`, etc. to name-based addressing (change 2 of 3); admin UI pages (change 3 of 3); list endpoints with status filter.

## Capabilities

### New Capabilities
- `user-create-no-worker`: Optional `--no-worker` flag on `user create` to create users with `worker_status = 'none'`.
- `user-rename`: Rename a user (and therefore their worker name) via `user rename <old> <new>`.
- `user-delete-safe`: `user delete <id>` blocks if the user is a worker; `user force-delete <id>` cascades.
- `worker-view`: Display a worker's complete profile, including status, for both active and inactive workers.
- `worker-deactivate`: Take a worker out of active scheduling while preserving configuration; reverse the action with `worker activate`.
- `worker-delete`: Safe-delete a worker (sets `worker_status = 'none'`); force-delete cascades.
- `worker-name-resolution`: Resolve worker name (= username) to `WorkerId`, distinguishing not-found from not-a-worker.
- `worker-status-filtering`: Scheduler and `WorkerContext` loaders SHALL only consider workers with `worker_status = 'active'`.

### Modified Capabilities
<!-- None at the spec level. Existing 30+ worker commands keep their `<wid>` shape; renamed in change 2. -->

## Impact

- **Schema:** `users` rebuilt with `worker_status` and `deactivated_at`; `users.worker_id` removed. All `worker_*` tables gain `REFERENCES users(id)` on their `worker_id` column. No data migration (system not deployed).
- **Domain types:** `WorkerStatus` enum (`Active`, `Inactive`, `None`) added. `userIdToWorkerId :: UserId -> WorkerId` helper.
- **Repository:** `repoCreateUser` signature changes (drops `WorkerId` parameter, adds `Bool` for noWorker). Adds `repoRenameUser`, `repoSetWorkerStatus`, `repoLoadWorkerStatus`, `repoListActiveWorkerIds`, `repoListWorkerIdsByStatus`, `repoCascadeWorkerSchedule`, `repoCascadeWorkerConfig`, `repoForceDeleteUser`. The existing `repoLoadWorkerCtx` is updated to filter by `worker_status = 'active'`.
- **Service:** New `Service/User.hs` with `renameUser`, `safeDeleteUser`, `forceDeleteUser`. `Service/Worker.hs` gains `WorkerReferences`, `checkWorkerReferences`, `safeDeactivateWorker` (clears pins/open drafts/future calendar), `activateWorker`, `safeDeleteWorker`, `forceDeleteWorker`, `viewWorker`, `WorkerProfile`.
- **CLI:** New constructors `UserRename`, `UserForceDelete`, `WorkerView`, `WorkerDeactivate`, `WorkerActivate`, `WorkerDelete`, `WorkerForceDelete`. `UserCreate` gains a `Bool` for `--no-worker`. Parser, `Resolve.hs`, `App.hs` executor, help text all updated. New `displayWorkerView` in `CLI/Display.hs`.
- **REST:** New routes and handlers (above). `Server/Json.hs` gets `RenameUserReq`, `WorkerProfile` ToJSON, `WorkerReferencesResp`. `CreateUserReq` extended.
- **Audit:** `Audit/CommandMeta.hs` updated for new verbs.
- **Scheduler:** `Domain/Scheduler.hs` (and any direct readers of worker tables) verified to receive only active workers via the updated `repoLoadWorkerCtx`.
- **Demo:** Verified to still pass — uses `user create` without `--no-worker`.
- **No external API consumers**, no production data, so this is safe to ship as a hard break.
