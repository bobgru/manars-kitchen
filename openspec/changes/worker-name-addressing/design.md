## Context

Change 1 of the worker-foundation roadmap (archived 2026-05-17 as `2026-05-17-worker-foundation`) made workers first-class:
- `users.worker_status` ∈ {`none`, `active`, `inactive`}.
- `WorkerId` value = `UserId` value.
- `Service.Worker.resolveWorkerByName :: Repository -> Text -> IO (Either ResolveWorkerError (WorkerId, WorkerStatus))`.
- `Server.Handlers.resolveWorkerName :: Repository -> Text -> Handler WorkerId` (translates resolver errors to 404).
- New CLI/REST surface for `worker view`, `worker deactivate`, `worker activate`, `worker delete`, `worker force-delete`.

But the older 30+ `worker <verb> <wid>` commands still take numeric `<wid>`, and the corresponding REST routes still use `:id` integer captures. The existing `name-based-entity-resolution` capability already routes most CLI worker verbs through the resolver (`commandEntityMap` in `src/CLI/Resolve.hs`), so CLI users can already pass names — but the constructors in `CLI/Commands.hs` still take `Int` and the REST routes still take `Int`. This change cleans both up.

## Goals / Non-Goals

**Goals:**
- Every worker-management CLI verb takes a worker name as its primary argument (numeric strings remain accepted for compatibility).
- Every worker-keyed REST route uses `:name` capture and resolves via `resolveWorkerName`.
- `pin`/`unpin`, `assign`/`unassign`, and `what-if` commands take worker names (and station/skill names where applicable).
- Demo, docs, and tests reflect the new surface.

**Non-Goals:**
- Admin UI (change 3 of 3).
- Renaming verb names.
- Adding a `worker create` verb (creation continues via `user create` per change 1).
- Schema or service-layer changes — none needed.

## Decisions

### Decision 1: Reuse the change-1 resolver everywhere

`Service.Worker.resolveWorkerByName` (CLI side) and `Server.Handlers.resolveWorkerName` (REST side) are the canonical resolvers. Every affected handler calls one of them.

**Why:** Single source of truth for the not-found / not-a-worker / found distinction. Inactive workers resolve fine — the operator can configure them; the scheduler still excludes them via the active-only `WorkerContext` filter.

### Decision 2: Resolver inputs accept names OR numeric strings

The existing `Resolve.hs` `resolveOne` already passes numeric arguments through unchanged. Names go through a username lookup. This preserves backward compatibility for any test, script, or muscle memory that still types numeric IDs.

**Why:** Free win. Removes user-visible friction. The downstream constructor takes `String`, so both shapes flow through identically.

### Decision 3: Constructor signatures change `Int → String` for the worker arg

`CLI/Commands.hs` constructors that currently take `Int` for the worker arg become `String`. The executor in `App.hs` resolves with `resolveWorkerByName` and operates on `WorkerId`.

**Alternatives considered:**
- Keep constructors as `Int` and resolve inside the parser. Rejected: `Resolve.hs` already runs before parsing, so by the time the parser sees the input it's already a numeric string for resolved names. But that means the parser can't distinguish "user typed `42`" from "resolver resolved `alice` to `42`." Keeping the constructor as `String` (and resolving in the executor) gives the executor access to the original input for error messages and for paths where we want the resolver's richer error categories.

  Update: in fact the change-1 resolver isn't run by `Resolve.hs`'s `resolveOne` — that lives in CLI/Resolve.hs and is its own machinery. To get the change-1 resolver's "not a worker" distinction, the executor must call `resolveWorkerByName` directly. So constructors take `String` and the executor resolves explicitly.

### Decision 4: `worker info` is unchanged

`worker info` dumps the entire `WorkerContext` and takes no worker argument. No change needed.

### Decision 5: Skill captures on `:id/skills/:skillId` become `:name/skills/:skillName`

The combined route currently has `Capture "id" Int :> "skills" :> Capture "skillId" SkillId`. Both captures become `Text`. The skill capture is resolved via the existing skill name resolution (skills already use names in their primary CRUD routes).

### Decision 6: REST request bodies that name a worker by id (e.g. `RequestAbsenceReq.rarWorkerId`) STAY numeric

`RequestAbsenceReq` carries `workerId :: Int` in its JSON body. Names go in the **path** (Capture); ids continue to flow through bodies for endpoints not keyed by worker in the URL. Absence requests aren't on the worker-keyed path; they POST to `/api/absences` with body. We're not touching that endpoint shape — it's not part of "worker-keyed routes."

**Why:** Limit blast radius. The CLI / web layer can still translate names to ids before sending those bodies. A future change could unify body shapes if needed.

### Decision 7: Pin and assign commands resolve worker AND station

`pin <name> <station-name> <day> <hour|shift>` — both args resolve via `Resolve.hs`. Constructors change `Int Int` → `String String`. Same for `unpin`, `assign`, `unassign`. The `assign` constructor also has a station arg today.

### Decision 8: Demo script verification

`demo/restaurant-setup.txt` largely already uses names because the resolver supports them on most worker-management verbs. Verify the demo replays clean against the updated surface; adjust any remaining numeric `<wid>` references.

## Risks / Trade-offs

- **[Risk]** Hardcoded numeric IDs in tests will fail at the REST layer when routes flip to `:name`. → **Mitigation:** Update `ApiSpec.hs` calls to pass usernames. About 15 spots; mechanical.

- **[Risk]** `Resolve.hs` and the change-1 `resolveWorkerByName` may diverge in behavior. The legacy resolver returns the user_id as a numeric string; the change-1 resolver returns a `WorkerId` and distinguishes "not a worker." → **Mitigation:** The CLI executor calls `resolveWorkerByName` directly for the new error categories. The legacy `Resolve.hs` path remains as a syntactic pre-pass.

- **[Risk]** Renaming existing API routes is a breaking change. → **Mitigation:** No external consumers. Web admin UI (change 3) hasn't been built yet.

- **[Trade-off]** Bodies that carry `workerId :: Int` are not migrated. The CLI client and (future) admin UI still need a name-to-id step for those bodies. Acceptable for now.

## Migration Plan

No data migration. Code-only change:

1. Update `CLI/Commands.hs` constructors and parser.
2. Update `App.hs` executor for each affected verb.
3. Update `Server/Api.hs` route types.
4. Update `Server/Handlers.hs` handlers.
5. Update `cli/CLI/RpcClient.hs` if any RPC executor branches on these constructors (the change-1 RpcClient stubs new commands as "not yet supported").
6. Update `test/ApiSpec.hs` call sites.
7. Update `demo/restaurant-setup.txt` if needed.
8. `stack clean && stack build && stack test && make fast-demo` end-to-end.

## Open Questions

None. Spec wording is concrete enough to drive implementation.
