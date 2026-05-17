## Context

Workers became first-class entities in change 1 (`worker-foundation`, archived 2026-05-17) and acquired name-based REST/CLI addressing in change 2 (`worker-name-addressing`, archived 2026-05-17). The `users.worker_id` column was removed; workers are now users with `worker_status IN ('none','active','inactive')`. CLI verbs (`worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`, `user create [--no-worker]`, `user rename`, `user delete`, `user force-delete`) and corresponding REST endpoints exist. The React admin shell has working `/skills` and `/stations` pages; the sidebar already links `/workers`, but the route 404s.

Two structural facts shape this change:

1. **`WorkerProfileResp` has 21 fields.** The detail page is not a stations-style copy-paste — most attributes have their own setter endpoint, and the natural UI granularity is per-section save. To keep this change small, the detail page ships **identity-only** (name, status, ids, role); the other sections render as read-only placeholder cards labeled "managed via CLI for now."
2. **`worker deactivate` commits unconditionally today.** A confirmation modal needs to show counts *before* the user commits, which means the verb needs a safe-then-force protocol mirroring `worker delete` / `worker force-delete`.

## Goals / Non-Goals

**Goals:**
- Operators can view, find, and filter workers from the admin UI without using the CLI.
- Operators can rename, deactivate (with preview), activate, and delete workers from the UI.
- Two-step deactivation (preview → confirm) is consistent across CLI and REST.
- The list page stays in sync when worker-affecting mutations originate elsewhere (CLI, other admin sessions, server-side jobs), including user-level mutations like rename or force-delete.

**Non-Goals:**
- No UI editors for employment, preferences, skills, station prefs, cross-training, pairing, or pin/draft/calendar interaction. These remain CLI-only and surface as read-only placeholder cards on the detail page.
- No bulk actions (multi-select rows, bulk deactivate, etc.).
- No worker creation wizard with pre-filled employment/skill defaults — create posts to `/api/users` with the same minimal fields the CLI uses (username, password, role, optional `noWorker` flag).
- No reclassification of `user rename`/`user force-delete` SSE events as `entityType="worker"`. The list page subscribes to both event types instead.

## Decisions

### Decision: Safe-then-force pattern for deactivate, mirroring delete

`PUT /api/workers/:name/deactivate` becomes a safe verb:
- Returns `204 No Content` if the worker has zero pins, zero draft entries, and zero future calendar entries.
- Returns `409 Conflict` with body `{pinsRemoved, draftsRemoved, calendarRemoved}` if any are nonzero. **No state change.**

`PUT /api/workers/:name/deactivate/force` always commits and returns `200 OK` with the same body shape (so the UI can show "Removed N pins…" toast).

CLI follows the same shape: `worker deactivate <name>` is safe; `worker force-deactivate <name>` commits.

**Alternatives considered:**
- `dryRun=true` query parameter: rejected — introduces a third mode (preview vs. commit vs. legacy), and the `worker delete` analog already established the safe/force vocabulary.
- Two-call protocol with a preview token: rejected — solves a TOCTOU problem (state changing between preview and commit) that's unlikely to bite for single-worker deactivation, at the cost of doubling round-trips on the routine path.
- Apply the change only to REST, keep CLI single-call: rejected — inconsistent with the established CLI safe/force pattern for `delete`, and with this user's stated preference for symmetry.

### Decision: Slim list-endpoint payload (`WorkerSummaryResp`)

`GET /api/workers?status=active|inactive|all` returns a list of:
```haskell
data WorkerSummaryResp = WorkerSummaryResp
    { wsrName        :: !Text
    , wsrRole        :: !Text
    , wsrStatus      :: !Text     -- "active" | "inactive" | "none"
    , wsrIsTemp      :: !Bool
    , wsrWeekendOnly :: !Bool
    , wsrSeniority   :: !Int
    }
```

**Alternatives considered:**
- Reuse `WorkerProfileResp` (full 21-field shape): rejected — sends ~5x the bytes per row, including fields that aren't visible in the table (skill list, pairing arrays, etc.).
- Even thinner shape (just name + status): rejected — the table header includes `isTemp`, `weekendOnly`, and `seniority` to differentiate workers at a glance.

### Decision: Status filter is a query param on the list endpoint, bound to URL

`/workers?status=active` (default `active`), `/workers?status=inactive`, `/workers?status=all`. The page reads from `useSearchParams`, sends the value to the server, and re-fetches on filter change. URL-bound filters are linkable and reload-stable.

**Alternatives considered:**
- Client-side filter over a single "all" fetch: rejected — for a 100-worker installation, fine; for thousands, the slim payload is still ~30 bytes/row, but server-side filtering matches the CLI's `worker list --status` model (when added later) and keeps the payload bounded.

### Decision: Subscribe `WorkersListPage` to both `worker` and `user` SSE events

`useEntityEvents("worker", load)` catches the worker-prefixed CLI mutations (deactivate/activate/delete/force-delete and the per-attribute setters from change 2). `useEntityEvents("user", load)` catches `user rename`, `user create`, `user force-delete` — all of which can affect what's displayed on the workers list:

- `user rename` changes a worker's display name.
- `user create` (without `--no-worker`) adds a new worker.
- `user force-delete` removes a worker silently.

The `WorkerDetailPage` subscribes the same way; rename in particular is the user-side event that updates the displayed name.

**Alternatives considered:**
- Reclassify `user rename`/`user create`/`user force-delete` as `entityType="worker"` when the target user is/becomes a worker: rejected — `Audit.CommandMeta.classify` is a pure string-parser without repo access, and threading repo state through it changes the architecture. Dual-subscription is one line at the call site and the over-refresh cost is negligible (one additional list query per admin user creation).
- Emit a synthetic `worker` event from the rename/create/force-delete handlers in addition to the `user` event: rejected — doubles event volume and leaks worker-vs-user knowledge into handlers that should be entity-agnostic.

### Decision: Identity-only detail page; other sections are placeholder cards

The detail page renders the rename field and Activate/Deactivate buttons in editable form. All 18 other `WorkerProfileResp` fields render in read-only placeholder cards labeled "Skills (3) — managed via CLI for now," "Employment — managed via CLI for now," etc. The cards exist so users can see the data; future changes can replace each card with an editable section.

**Alternatives considered:**
- Ship full per-section editing in this change: rejected — would touch ~20 setter endpoints in the UI, each with its own form; outsizes the user's stated preference for small changes.
- Hide the placeholder cards entirely: rejected — operators benefit from seeing the values even when they can't edit them; the placeholder also signals what's intentionally deferred.

### Decision: Two create buttons (`[New Worker]` and `[New User (no worker)]`)

Both buttons open the same minimal form (username, password, role) and POST to `/api/users`. The "no worker" button passes `noWorker: true`. The label is explicit rather than aliasing — "Admin User" would be wrong for non-admin non-workers, and a dropdown hides the choice the model already exposes.

If `POST /api/users` doesn't currently expose the `noWorker` flag (added in change 1's CLI), this change adds it.

## Risks / Trade-offs

- **TOCTOU between deactivate-safe and deactivate-force calls.** State could change (e.g., a draft entry is added) between the safe call's count and the force call's commit. Mitigation: accept the risk for routine ops; the force call's response includes actual removed counts, so the UI can show "actually removed N (different from preview)" if it cares. Likely won't bite in practice.
- **CLI behavior change is breaking.** Anyone scripting `worker deactivate` today needs to switch to `worker force-deactivate` to preserve current semantics. Mitigation: update CLI help and the README; consistent with how `worker delete` / `worker force-delete` already split.
- **Dual SSE subscription causes over-refresh.** Admin user creation reloads the workers list even though a non-worker user was added. The list query is small and infrequent; acceptable. If it becomes painful, the Decision above flags the alternative.
- **Placeholder cards on the detail page may confuse users into thinking the UI is broken.** Mitigation: label cards clearly with "managed via CLI for now"; show actual values read-only so operators can verify them.
- **Pairing references store names, not IDs.** When a worker is renamed, every other worker's `avoidPairing`/`preferPairing` arrays go stale on display. Mitigation: the dual SSE subscription's `user` channel catches rename events and reloads the list/detail. The detail page's pairing placeholder card displays current values, so reload is sufficient.

## Migration Plan

No DB schema changes; no data migration. Deployment is a single binary rebuild + frontend bundle swap.

Backward-compatible deployment order doesn't matter because the system isn't deployed (per change 1's archived design). For future deployments, the breaking CLI change in `worker deactivate` semantics would warrant a CHANGELOG entry highlighting the new safe/force split.

## Open Questions

- Whether `POST /api/users` already accepts the `noWorker` flag in REST (it definitely accepts it from CLI). Resolved during implementation: if missing, add it as part of this change's task list.
