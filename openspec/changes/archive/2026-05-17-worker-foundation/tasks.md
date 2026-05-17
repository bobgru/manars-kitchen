## 1. Schema and Repository

- [x] 1.1 Update `Repo/Schema.hs` `users` table: drop `worker_id`, add `worker_status TEXT NOT NULL DEFAULT 'active' CHECK (worker_status IN ('none','active','inactive'))`, add `deactivated_at TEXT` (nullable). No data migration; the database is dropped and recreated.
- [x] 1.2 Update every `worker_*` table in `Repo/Schema.hs` to declare `worker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT`. Cover: `worker_skills`, `worker_hours`, `worker_overtime_optin`, `worker_station_prefs`, `worker_prefers_variety`, `worker_shift_prefs`, `worker_weekend_only`, `worker_seniority`, `worker_avoid_pairing`, `worker_prefer_pairing`, `worker_cross_training`, `worker_employment`. Also add `REFERENCES users(id)` to `worker_id` in `pinned_assignments`, `calendar_assignments`, `draft_assignments`, `assignments`, `absence_requests`, `yearly_allowances`.
- [x] 1.3 Add `WorkerStatus` data type (`Active | Inactive | None`) in `Domain/Types.hs` (or a new `Domain/User.hs`); add `userIdToWorkerId :: UserId -> WorkerId` and `workerIdToUserId :: WorkerId -> UserId` helpers.
- [x] 1.4 Update `repoCreateUser` signature in `Repo/Types.hs` from `Text -> Text -> Role -> WorkerId -> IO UserId` to `Text -> Text -> Role -> Bool -> IO UserId` (the Bool = `noWorker`). The created user has `worker_status = 'none'` if `noWorker = True`, else `'active'`.
- [x] 1.5 Update `sqlCreateUser` in `Repo/SQLite.hs` for the new signature; remove `worker_id` from the INSERT.
- [x] 1.6 Update `repoGetUser`, `repoGetUserByName`, `repoListUsers` in `Repo/SQLite.hs` to read `worker_status` and `deactivated_at` instead of `worker_id`. Update the `User` record in `Auth/Types.hs` accordingly: replace `userWorkerId :: WorkerId` with `userWorkerStatus :: WorkerStatus` and add `userDeactivatedAt :: Maybe Day`. (The integer-equal-to-userId reading of WorkerId is computed in callers.)
- [x] 1.7 Add `repoRenameUser :: UserId -> Text -> IO ()` and implement `sqlRenameUser` (UPDATE users SET username = ? WHERE id = ?; reject collision via UNIQUE).
- [x] 1.8 Add `repoSetWorkerStatus :: UserId -> WorkerStatus -> Maybe Day -> IO ()` (UPDATE users SET worker_status = ?, deactivated_at = ?).
- [x] 1.9 Add `repoLoadActiveWorkerIds :: IO [WorkerId]` and `repoLoadWorkerIdsByStatus :: WorkerStatus -> IO [WorkerId]`.
- [x] 1.10 Update `repoLoadWorkerCtx` in `Repo/SQLite.hs` to inner-join `users` on `worker_id = users.id` and filter `users.worker_status = 'active'` for every SELECT it issues.
- [x] 1.11 Update `repoLoadEmployment` similarly so inactive workers are excluded.
- [x] 1.12 Add `repoCascadeWorkerConfig :: WorkerId -> IO ()` that DELETEs from all worker configuration tables (`worker_skills`, `worker_hours`, `worker_overtime_optin`, `worker_station_prefs`, `worker_prefers_variety`, `worker_shift_prefs`, `worker_weekend_only`, `worker_seniority`, `worker_avoid_pairing`, `worker_prefer_pairing`, `worker_cross_training`, `worker_employment`) for that worker_id (also the symmetric counterpart in pairing tables).
- [x] 1.13 Add `repoCascadeWorkerSchedule :: WorkerId -> IO ()` that DELETEs from `pinned_assignments`, `calendar_assignments`, `draft_assignments`, `assignments`, `absence_requests`, `yearly_allowances` for that worker_id.
- [x] 1.14 Add `repoDeactivateClearings :: WorkerId -> Day -> IO (Int, Int, Int)` that DELETEs pins, all draft entries for that worker, and `calendar_assignments WHERE slot_date >= today`. Returns counts (pins, drafts, calendar).
- [x] 1.15 Add `repoForceDeleteUser :: UserId -> IO ()` that calls `repoCascadeWorkerSchedule` then `repoCascadeWorkerConfig` then `DELETE FROM users WHERE id = ?`.
- [x] 1.16 Update existing call sites of `repoCreateUser` (CLI `UserCreate`, demo replay path, server) to pass the `Bool` flag and remove `worker_id` allocation logic in `App.hs` (~line 1621).

## 2. Service Layer

- [x] 2.1 Create `Service/User.hs` with `renameUser :: Repository -> UserId -> Text -> IO (Either String ())` (rejects on collision/not-found), `safeDeleteUser :: Repository -> UserId -> IO (Either String ())` (returns Left when user has worker_status active/inactive), `forceDeleteUser :: Repository -> UserId -> IO ()`.
- [x] 2.2 In `Service/Worker.hs` add `WorkerReferences` record: counts and short context lists for every worker reference table (configuration set: skills, employment, hours, overtime opt-in, station prefs, prefers variety, shift prefs, weekend only, seniority, avoid pairing, prefer pairing, cross-training; schedule set: pinned, calendar (any date), draft, schedule assignments, absences, allowances).
- [x] 2.3 Add `checkWorkerReferences :: Repository -> WorkerId -> IO WorkerReferences`.
- [x] 2.4 Add `isWorkerUnreferenced :: WorkerReferences -> Bool` (true iff every group is empty).
- [x] 2.5 Add `safeDeactivateWorker :: Repository -> WorkerId -> Day -> IO (Either String DeactivateResult)` that loads the user's status; if `none`, return Left "not a worker"; if `inactive`, Left "already inactive"; if `active`, call `repoDeactivateClearings`, then `repoSetWorkerStatus uid Inactive (Just today)`. `DeactivateResult` carries the cleared counts.
- [x] 2.6 Add `activateWorker :: Repository -> WorkerId -> IO (Either String ())` that flips status `Inactive` → `Active` and clears `deactivated_at`.
- [x] 2.7 Add `safeDeleteWorker :: Repository -> WorkerId -> IO (Either WorkerReferences ())` that runs `checkWorkerReferences`; if any group non-empty, Left; else `repoSetWorkerStatus uid None Nothing`.
- [x] 2.8 Add `forceDeleteWorker :: Repository -> WorkerId -> IO ()` that calls `repoCascadeWorkerSchedule`, `repoCascadeWorkerConfig`, then `repoSetWorkerStatus uid None Nothing`.
- [x] 2.9 Add `viewWorker :: Repository -> WorkerId -> IO WorkerProfile` and `WorkerProfile` record including status, deactivatedAt, employment, hours, prefs, pairings, seniority, cross-training, granted skills (resolved to names where applicable).
- [x] 2.10 Update `Service/Auth.hs` (or wherever user creation lives) to accept the `noWorker` flag.

## 3. CLI Commands

- [x] 3.1 Add command constructors in `CLI/Commands.hs`: `UserRename String String`, `UserForceDelete Int`, `WorkerView String`, `WorkerDeactivate String`, `WorkerActivate String`, `WorkerDelete String`, `WorkerForceDelete String`. Update `UserCreate` to `UserCreate String String String Bool` (the Bool = noWorker).
- [x] 3.2 Update parser in `CLI/Commands.hs`:
  - `user create <name> <pass> <role>` and `user create <name> <pass> <role> --no-worker`
  - `user rename <old> <new>`
  - `user force-delete <id>`
  - `worker view <name>`
  - `worker deactivate <name>`
  - `worker activate <name>`
  - `worker delete <name>`
  - `worker force-delete <name>`
- [x] 3.3 Update `Resolve.hs` `commandEntityMap` for the new verbs (`user rename`, `user force-delete`, `worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`).
- [x] 3.4 Update CLI executor in `App.hs`:
  - `UserCreate` no longer allocates worker_id; passes the Bool to `repoCreateUser`.
  - `UserRename` calls `Service.User.renameUser`.
  - `UserDelete` becomes safe-delete: if user's `worker_status` is `active` or `inactive`, print message and abort; else delete.
  - `UserForceDelete` calls `Service.User.forceDeleteUser`.
  - `WorkerView` resolves name → WorkerId, calls `viewWorker`, calls `displayWorkerView`.
  - `WorkerDeactivate` resolves name → WorkerId, calls `safeDeactivateWorker today`, prints summary counts.
  - `WorkerActivate` resolves name → WorkerId, calls `activateWorker`.
  - `WorkerDelete` resolves name → WorkerId, calls `safeDeleteWorker`; prints references if blocked.
  - `WorkerForceDelete` resolves name → WorkerId, calls `forceDeleteWorker`.
- [x] 3.5 Add `resolveWorkerName :: Repository -> String -> IO (Either ResolveError WorkerId)` distinguishing not-found, not-a-worker, and worker (active or inactive).
- [x] 3.6 Update help text in `App.hs` `commandRows` to add the new verbs.

## 4. Audit Log

- [x] 4.1 Update `classifyUser` (or add) in `Audit/CommandMeta.hs` for `user rename`, `user force-delete`.
- [x] 4.2 Update `classifyWorker` in `Audit/CommandMeta.hs` for `worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`.

## 5. REST API

- [x] 5.1 Update `CreateUserReq` in `Server/Json.hs`: add `cusrNoWorker :: Bool` parsed via `.:? "noWorker" .!= False`.
- [x] 5.2 Add `RenameUserReq` JSON type with `Text` field `name`.
- [x] 5.3 Add `WorkerProfile` ToJSON for the view response (includes `status`, `deactivatedAt`, employment, prefs, etc.).
- [x] 5.4 Add `WorkerReferencesResp` JSON type mirroring `StationReferencesResp` pattern, with `configuration` and `schedule` groups.
- [x] 5.5 Add `DeactivateResultResp` JSON type with `pinsRemoved`, `draftsRemoved`, `calendarRemoved` Int fields.
- [x] 5.6 Update server route types in `Server/Api.hs`:
  - `PUT /api/users/:id/rename` with `RenameUserReq`.
  - `DELETE /api/users/:id` (existing route; safe-delete semantics).
  - `DELETE /api/users/:id/force`.
  - `GET /api/workers/:name`.
  - `PUT /api/workers/:name/deactivate`.
  - `PUT /api/workers/:name/activate`.
  - `DELETE /api/workers/:name`.
  - `DELETE /api/workers/:name/force`.
- [x] 5.7 Add `resolveWorkerName :: Repository -> Text -> Handler WorkerId` returning 404 for not-found and a distinct status for not-a-worker.
- [x] 5.8 Add handlers `handleRenameUser`, `handleForceDeleteUser`, `handleViewWorker`, `handleDeactivateWorker`, `handleActivateWorker`, `handleDeleteWorker`, `handleForceDeleteWorker`. Update `handleDeleteUser` for safe-delete semantics. Update `handleCreateUser` to pass `cusrNoWorker`.
- [x] 5.9 Wire all updated/new handlers in `Server/Api.hs`.

## 6. CLI Display

- [x] 6.1 Add `displayWorkerView :: WorkerProfile -> IO ()` in `CLI/Display.hs`. Sections in order: name + worker_id + role, status + deactivated_at (when inactive), employment, hours + overtime opt-in, flags (weekend-only, prefers-variety), seniority, granted skills (names), station prefs (names, in order), shift prefs, cross-training (skill names), avoid-pairing (worker names), prefer-pairing (worker names). Empty sections explicit.

## 7. Verify

- [x] 7.1 Drop and recreate the demo database; run `stack clean`, then `stack build`. Fix all warnings.
- [x] 7.2 Run `stack test`. Fix failures. Ensure tests cover: scheduler ignores inactive workers; worker view for active/inactive/non-worker; deactivate clears pins+drafts+future calendar but preserves config and past calendar; activate restores nothing but flips status; safe vs. force delete; user delete blocked when user is a worker.
- [x] 7.3 Run the demo end-to-end and verify it completes successfully.
- [x] 7.4 Manually exercise via the CLI: create a non-worker user; rename a worker; view active and inactive; deactivate then re-view; activate; delete a freshly-created (no-config) worker; force-delete a worker with config and assignments; user delete a non-worker; user force-delete a worker user.
- [x] 7.5 Manually test the new REST endpoints via curl, including the 409 path with `WorkerReferencesResp`.
