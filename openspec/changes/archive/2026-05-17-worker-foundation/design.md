## Context

Two related-but-distinct concepts:
- **User**: an account that can log in (`users` table).
- **Worker**: an entity that participates in scheduling, identified by a `WorkerId` integer and referenced from many `worker_*` tables.

Today, "worker" is implicit: a user with a non-null `worker_id`. The `worker_id` is allocated as `MAX(users.worker_id) + 1`. There is no `workers` table, no FK from `worker_*` tables to users, and no way to take a worker out of scheduling without deleting their configuration. Operators have asked for a "leaves on good terms, may return" workflow.

The just-archived `2026-05-16-station-crud` change established the pattern for view/rename/safe-delete/force-delete on an entity. Worker is more complex because:
- Worker name = `users.username`. Rename therefore lives on `user`.
- Worker references span ~13 `worker_*` tables plus calendar/draft/assignment/absence/allowance tables.
- 30+ existing `worker <verb> <wid>` commands address workers by integer ID. Renaming all of them is large enough to merit its own change (this change is 1 of a 3-change sequence).
- Workers need an "inactive" state, distinct from "deleted" and "non-worker."

The system has not been deployed. The database can be dropped and recreated. No data migration is required.

## Goals / Non-Goals

**Goals:**
- Eliminate the separate `worker_id` allocation: `WorkerId` value = `UserId` value.
- Add a three-valued `worker_status` on users: `none` / `active` / `inactive`.
- Provide deactivate/activate as the routine "remove from scheduling, may return" workflow.
- Provide a safe-delete and force-delete for the rare "remove the worker concept entirely" case.
- Make worker view, rename (via user rename), and admin commands by-name (= username).
- Have the scheduler and `WorkerContext` loader filter to `active` automatically.
- Establish real foreign keys from `worker_*` tables to `users(id)`.

**Non-Goals:**
- Switching the existing 30+ `worker <verb> <wid>` CLI commands to name-based addressing (change 2 of 3).
- Admin UI pages for workers (change 3 of 3).
- A separate `workers` table.
- A list endpoint for workers with status filtering — view-by-name is sufficient for change 1.
- Migrating production data (none exists).

## Decisions

### Decision 1: Worker name = `users.username`; no separate workers table

Workers always have a user account; usernames are already unique; a separate name field would invite drift. Rename therefore lives on `user rename` — it's the only verb. Confirmed by user.

### Decision 2: `WorkerId` value = `UserId` value; newtypes stay distinct

Because every worker has exactly one user and vice versa (when worker_status ≠ 'none'), the integers are interchangeable. We exploit this:
- Drop `users.worker_id` entirely.
- Replace with `worker_status TEXT` and `deactivated_at TEXT`.
- Allocation logic in `App.hs` (~line 1621) goes away.
- All `worker_*.worker_id` columns gain `REFERENCES users(id) ON DELETE RESTRICT`.

The Haskell-level `WorkerId` and `UserId` newtypes stay distinct to avoid touching the ~100 call sites that destructure `WorkerId`. The only conversion is the new helper `userIdToWorkerId :: UserId -> WorkerId`. The reverse direction (`workerIdToUserId`) is also added for the rare lookup paths (resolving worker name needs to read `users` then return a `WorkerId`).

**Alternative considered:** collapse `WorkerId` and `UserId` into a single newtype. Rejected — too invasive for change 1, and the type-level distinction has been useful for catching bugs in the past.

### Decision 3: Three-valued status on users (`none` / `active` / `inactive`)

`none` = the user is admin-only or otherwise non-scheduling. `active` = currently being scheduled. `inactive` = was a worker, configuration preserved, not currently scheduled, can be reactivated.

**Schema:**
```sql
worker_status TEXT NOT NULL DEFAULT 'active' CHECK (worker_status IN ('none','active','inactive')),
deactivated_at TEXT  -- ISO date, NULL when status != 'inactive'
```

**Why a single column instead of two booleans:** `is_worker + is_active` produces a meaningless `is_worker=false, is_active=true` combination. A `worker_status` enum eliminates the impossible state.

**Why `deactivated_at`:** operators want to know when someone was deactivated. The audit log already captures the event, but a denormalized timestamp on the user row makes `worker view` cheap and obvious. Cleared on reactivation.

### Decision 4: Inactivation clears pins, open drafts, AND future calendar assignments

Confirmed by user. The system removes from `pinned_assignments`, `draft_assignments` for any non-archived draft, and `calendar_assignments WHERE slot_date >= today()`. Past calendar history is preserved. Named-schedule assignments (`assignments` table) are preserved.

**Implication:** `worker deactivate` produces visible side effects beyond the status flip. The CLI message reports counts: "Deactivated alice. Removed 3 pins, 2 draft entries, 8 future calendar slots." The audit log records the deactivation only (the cascaded deletions are part of the operation, not separately classified).

**Trade-off:** The operator may want to know which slots were cleared. For change 1, we only print counts; a richer summary can come later.

### Decision 5: Reactivation does not restore cleared assignments

When `worker activate` is called, the old pins/drafts/calendar entries that were cleared on deactivation are not restored. The operator regenerates as needed. Configuration (skills, prefs, employment) survives the round-trip and is the principal value of the workflow.

**Alternative considered:** snapshot pins to a side table on deactivation; restore on reactivation. Rejected — adds complexity for a feature operators can replicate manually if needed.

### Decision 6: Scheduler filters to `worker_status = 'active'` via the context loader

`repoLoadWorkerCtx` and `repoLoadEmployment` are updated to inner-join `users` on `worker_id = users.id` and filter `users.worker_status = 'active'`. Downstream code (scheduler, hint engine, draft validation) operates on the loaded `WorkerContext` and therefore sees only active workers. This avoids touching every scheduler call site.

**Risk:** Any code path that bypasses the context loader and queries `worker_*` tables directly would still see inactive workers. **Mitigation:** Audit the codebase during implementation; document the invariant; ideally the FK constraint plus filtered views are the only access paths. The repository functions that return raw `worker_id` lists should grow status-aware variants if they exist.

### Decision 7: Verb names — `deactivate` / `activate`, `delete` / `force-delete`

Confirmed by user. Symmetric with the rest of the codebase. `deactivate` is the routine verb; `delete` is the "I'm sure" variant.

**Operator decision tree:**
- "This person isn't working right now but might come back" → `worker deactivate <name>`
- "This person isn't a worker anymore but I want to keep configs" → still `worker deactivate <name>`. There is no separate "demote without losing config" verb because deactivated covers it.
- "Remove the worker concept; this user shouldn't have worker config at all" → `worker delete <name>` (blocks if any refs anywhere) or `worker force-delete <name>` (cascades).
- "Get rid of the user account too" → `worker force-delete` then `user delete`, or `user force-delete <id>` directly.

### Decision 8: `worker delete` references include EVERYTHING

Unlike `worker deactivate`, which is the routine workflow, `worker delete` is the rare "no, really, this person was never really a worker" path. Its safe-delete check looks at every reference table (configuration AND schedule history). If anything is found, the operator is told to either deactivate, address the references, or use `force-delete`.

The configuration vs. schedule grouping in the error output helps the operator decide whether they actually wanted `deactivate`.

### Decision 9: REST endpoint shape

- `GET /api/workers/:name` → 200 with profile JSON; 404 if user not found; 404 if `worker_status = 'none'`.
- `PUT /api/workers/:name/deactivate` → 200 with summary counts.
- `PUT /api/workers/:name/activate` → 200.
- `DELETE /api/workers/:name` → 204 on success; 409 with `WorkerReferencesResp` if blocked; 400/422 if user is `none` or `inactive` (suggest `force-delete` for inactive with refs).
- `DELETE /api/workers/:name/force` → 204.
- `PUT /api/users/:id/rename` body `{"name": "..."}` → 200; 409 on collision.
- `DELETE /api/users/:id` (existing route, semantics changed) → 204; 409 with `WorkerReferencesResp` if user is a worker.
- `DELETE /api/users/:id/force` → 204.
- `POST /api/users` body extended with optional `noWorker: bool`.

Listing workers is **not** added in this change. The existing `/api/users` endpoint already lists users; status filtering on that endpoint can come with change 3.

### Decision 10: New service module: `Service/User.hs`

`Service/Worker.hs` already houses worker-context plumbing. User-level operations (`renameUser`, `safeDeleteUser`, `forceDeleteUser`) belong in a new `Service/User.hs`. Worker-level (status changes, view, references, safe/force-delete of the worker concept) stays in `Service/Worker.hs`.

## Risks / Trade-offs

- **[Risk]** Code paths that bypass `repoLoadWorkerCtx` and query `worker_*` directly would see inactive workers. → **Mitigation:** Inventory direct-query sites during implementation; ensure the FK + filtered context are the only access paths used by the scheduler. Add a focused test that an inactive worker is not assigned.

- **[Risk]** Future calendar deletion on deactivation is destructive and partially irreversible. → **Mitigation:** Print counts in the CLI message and log via audit. Reactivation does not restore. Operators must understand this; it's documented in CLI help and the audit log preserves the event.

- **[Risk]** FKs may surface previously-undetected orphan rows when the database is recreated. → **Mitigation:** None of the existing test fixtures should produce orphans, but the test run after schema rebuild will catch any.

- **[Trade-off]** `WorkerId` value = `UserId` value invites confusion. → Mitigation: keep newtypes distinct; require explicit `userIdToWorkerId` conversion at boundaries; document the equivalence in `Domain/Types.hs`.

- **[Trade-off]** Snapshot-and-restore on reactivation would be friendlier but adds tables, code, and tests. Operators can re-pin manually.

## Migration Plan

There is no data migration. The system has never been deployed.

- New schema is the canonical schema; existing development databases are dropped and recreated.
- Existing demo replay scripts are reviewed — they use `user create` without `--no-worker`, so they continue to produce active workers.
- After merge, run `stack test` and the demo end-to-end to verify.

## Open Questions

None remaining. Roadmap notes:
- Change 2 of 3: name-based addressing for the existing 30+ `worker <verb> <wid>` commands and their REST endpoints.
- Change 3 of 3: React admin UI (`WorkersListPage` with status filter, `WorkerDetailPage`).
