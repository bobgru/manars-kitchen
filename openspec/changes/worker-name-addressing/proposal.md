## Why

Change 1 of the worker-foundation roadmap (archived 2026-05-17) made workers first-class with view/deactivate/delete by name and added a `resolveWorkerByName` resolver, but the existing 30+ `worker <verb> <wid>` CLI commands and their REST endpoints still take numeric `<wid>` arguments. That leaves the system inconsistent: a manager creates `alice` by name, but then has to look up `alice`'s numeric worker_id to grant her a skill or set her hours.

Some scaffolding already exists — `name-based-entity-resolution` accepts names in many places — but the rest of the worker surface (REST routes especially) still uses `:id` captures. This change finishes the migration so every worker-management surface is name-addressed.

## What Changes

- **CLI:** All `worker <verb> <wid> ...` commands take a worker name (= username) instead of a numeric `<wid>`. The 18 affected verbs:
  - `grant-skill`, `revoke-skill`, `set-hours`, `set-overtime`, `set-prefs`, `set-shift-pref`, `set-variety`, `set-weekend-only`, `set-status`, `set-overtime-model`, `set-pay-tracking`, `set-temp`, `set-seniority`, `set-cross-training`, `clear-cross-training`, `avoid-pairing`, `clear-avoid-pairing`, `prefer-pairing`, `clear-prefer-pairing`.
- **CLI:** `worker grant-skill`, `worker revoke-skill`, `worker set-cross-training`, `worker clear-cross-training` now take skill **names** for the second argument (already supported by `Resolve.hs`'s `EWorker, ESkill` mapping; this change verifies and extends).
- **CLI:** `worker set-prefs` takes station names for the trailing arg list.
- **CLI:** `pin <name> <station-name> <day> <hour|shift>` and `unpin ...` use names.
- **CLI:** `assign <sched> <name> <station-name> <date> <hour>` and `unassign ...` use names.
- **CLI:** `what-if pin <name> <station-name> <date> <hour>`, `what-if grant-skill <name> <skill-name>`, `what-if waive-overtime <name>`, `what-if override-prefs <name> <station-names...>` all take names.
- **CLI Commands.hs:** Constructors for these commands change from `Int` (or `Int Int ...`) to `String` (or `String String ...`). Executor in `App.hs` resolves names via `Service.Worker.resolveWorkerByName` (and the existing skill/station resolvers) at the top of each handler.
- **REST:** All `/api/workers/:id/...` routes change to `/api/workers/:name/...`. Affected: `:id/hours`, `:id/overtime`, `:id/prefs`, `:id/variety`, `:id/shift-prefs`, `:id/weekend-only`, `:id/seniority`, `:id/cross-training`, `:id/employment-status`, `:id/overtime-model`, `:id/pay-tracking`, `:id/temp`, `:id/skills/:skillId`, `:id/avoid-pairing`, `:id/prefer-pairing`. Skill-grant routes change `Capture "skillId" SkillId` to `Capture "skillName" Text`.
- **REST:** `/api/pins` route bodies now carry worker names and station names (verify or update `PinReq` JSON shape).
- **REST handlers:** Every handler swaps its `Int` capture for `Text`, calls the existing `resolveWorkerName :: Repository -> Text -> Handler WorkerId` from change 1, and proceeds. Same for skill name captures.
- **`Resolve.hs`:** Verify the `commandEntityMap` lists every command above with `Resolve EWorker` (and friends). Verify the resolver outputs the worker_id correctly under the new `worker_id == user_id` model. The existing resolver maps name → id-string, so callers continue to pattern-match on `Int` after parsing — no caller change needed beyond the constructor signature update.
- **Audit log:** Verb names unchanged; `cmEntityId` continues to record numeric IDs (since that's what's stored). The original command string still has names.
- **Demo:** Update `demo/restaurant-setup.txt` to use names where it currently uses ids (it mostly already does, since the resolver was active for many of these — verify and adjust).
- **Out of scope (deferred):** Admin UI (change 3 of 3); backwards-compatible numeric-id acceptance (the resolver already permits numeric strings to pass through, so this is preserved automatically).

## Capabilities

### New Capabilities
- `worker-cli-name-args`: All worker-management CLI verbs accept a worker name as the primary argument; numeric IDs continue to work.
- `worker-rest-name-routes`: All worker-keyed REST routes use `:name` capture and resolve via the change-1 `resolveWorkerName`.
- `pin-name-args`: `pin` / `unpin` CLI commands and their REST endpoints take worker name and station name.
- `assign-name-args`: `schedule assign` / `schedule unassign` CLI commands take worker name and station name.
- `what-if-name-args`: `what-if` commands that reference workers take worker names; existing skill/station name resolution preserved.

### Modified Capabilities
- `name-based-entity-resolution`: Extends the existing capability to cover the full worker surface. The previous spec said "names work in many places"; this change tightens the contract to "names work everywhere a worker is referenced." Adds explicit scenarios for the 18 worker verbs, `pin`/`unpin`, `assign`/`unassign`, and `what-if` commands. Notes that the resolver delegates to `Service.Worker.resolveWorkerByName` from change 1, which distinguishes "not a worker" from "not found."

## Impact

- **Domain:** No changes.
- **Repository:** No changes.
- **Service:** No changes (resolver and worker operations already exist from change 1).
- **CLI commands.hs:** ~19 constructor signature changes (Int → String for the worker arg in each); pin/unpin/assign/unassign also change station args (Int → String) and skill args where applicable.
- **CLI parser:** Each affected pattern updates from `[isDigit' wid, ...]` guards to plain string capture. Most patterns already accept either via the resolver, so this is mostly removal of guards.
- **CLI App.hs executor:** Each affected handler resolves the name to a `WorkerId` (and skill/station names to ids) before invoking the service function. About 19 small handler edits.
- **REST Server/Api.hs:** Every `Capture "id" Int` on a worker-keyed route changes to `Capture "name" Text`. About 15 route lines.
- **REST Handlers.hs:** Every affected handler swaps the `Int` parameter for `Text`, calls `resolveWorkerName`, and continues. The `:id/skills/:skillId` route also swaps `SkillId` capture for `Text` and calls a skill resolver. About 15 handler edits.
- **REST RpcClient.hs (test):** The test client mirrors the API type; updates flow naturally from the `Server/Api.hs` changes.
- **Demo:** `demo/restaurant-setup.txt` reviewed and adjusted as needed.
- **Tests:** `ApiSpec.hs` calls the REST endpoints with hardcoded numeric IDs for worker captures; these become hardcoded names. Roughly the same number of edits as REST handlers.
- **Breaking:** REST API shape changes for ~15 endpoints. No external consumers exist; web admin UI is in change 3 (still TBD). CLI surface stays compatible because the resolver still accepts numeric strings.
