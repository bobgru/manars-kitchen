## Context

Skills currently support create, list, rename, info, implication management, and worker grant/revoke. The missing operations are delete, view (single-skill info), and UI creation/deletion. The existing `removeSkill` in the service layer does a bulk SQL wipe — it won't produce per-reference audit entries needed for a future undo feature.

Key codebase state:

- `SkillId` newtype exists in `Domain/Types.hs` but raw `Int` is used in `Commands.hs` ADT variants, `Server/Api.hs` Capture types, and `Server/Handlers.hs` parameters.
- No `FromHttpApiData`/`ToHttpApiData` instances exist for any ID newtype — this will be the first.
- The database has `PRAGMA foreign_keys=ON` but no `REFERENCES` clauses on any table.
- `sqlDeleteSkill` misses `worker_cross_training` cleanup.
- `station require-skill` exists but has no inverse `station remove-required-skill`.
- The server already has `DELETE /api/skills/:id` which calls `removeSkill` (the bulk wipe). This endpoint must be replaced with safe-delete semantics.

## Goals / Non-Goals

**Goals:**

- Complete CRUD for skills: add delete (safe + force), view, UI create/delete
- Establish the force-delete-as-macro pattern (individual auditable commands) for future undo
- Propagate `SkillId` through CLI and server layers, establishing the `FromHttpApiData` pattern
- Add FK constraints for `skill_id` as a DB-level safety net
- Add `station remove-required-skill` command (needed by force-delete, useful independently)
- Add `skill rename` to CLI help text

**Non-Goals:**

- Delete/force-delete for other entities
- FK constraints for non-skill foreign keys
- Undo/redo implementation
- Skill description editing

## Decisions

### 1. Force-delete dispatches through `handleCommand`

Force-delete builds a list of `Command` values and passes each through the existing `handleCommand :: AppState -> Command -> IO ()` function. This ensures each sub-operation gets full audit logging, SSE event publication, and session touch behavior — identical to what would happen if the user typed each command manually.

**Alternative considered:** Call service-layer functions directly and manually write audit entries. Rejected because it duplicates the audit/event logic and could drift from the real command behavior.

**Alternative considered:** Build command strings and re-parse them. Rejected because it's fragile (quoting, name resolution) and the `Command` ADT is already available.

### 2. Safe delete queries references at the service layer

A new service function `checkSkillReferences :: Repository -> SkillId -> IO SkillReferences` returns a structured record of all references to a skill:

```haskell
data SkillReferences = SkillReferences
    { srWorkers        :: [(WorkerId, String)]    -- workers who have the skill (id, name)
    , srStations       :: [(StationId, String)]   -- stations requiring the skill (id, name)
    , srCrossTraining  :: [(WorkerId, String)]     -- workers cross-training toward it (id, name)
    , srImpliedBy      :: [(SkillId, String)]      -- skills that imply this one (id, name)
    , srImplies        :: [(SkillId, String)]      -- skills this one implies (id, name)
    }
```

This data serves three purposes: (a) safe-delete checks if all lists are empty, (b) the CLI error message lists what's blocking deletion, (c) the API returns it as a 409 response body so the UI can display it in the confirmation dialog.

### 3. `SkillId` in Servant via `FromHttpApiData`

Add instances to `Domain/Types.hs`:

```haskell
instance FromHttpApiData SkillId where
    parseUrlPiece t = SkillId <$> parseUrlPiece t

instance ToHttpApiData SkillId where
    toUrlPiece (SkillId i) = toUrlPiece i
```

Then change `Capture "id" Int` to `Capture "id" SkillId` in `Server/Api.hs`. Handler functions receive `SkillId` directly, eliminating manual wrapping like `SkillId sid`.

The `web-http-api-data` package provides `FromHttpApiData`/`ToHttpApiData`. It's likely already a transitive dependency of `servant-server` but may need to be added explicitly to the package.yaml/cabal file.

### 4. Two API endpoints for delete

- `DELETE /api/skills/:id` — safe delete. Returns 200 on success, 409 with `SkillReferences` JSON on conflict.
- `DELETE /api/skills/:id/force` — force delete. Dispatches individual removal commands, then safe-deletes the now-unreferenced skill.

The existing `DELETE /api/skills/:id` endpoint changes behavior from force-delete to safe-delete. This is a breaking change but acceptable since the UI is the only consumer and will be updated in the same change.

### 5. `skill view` reuses `SkillContext` and `WorkerContext` data

`skill view <id>` loads `SkillContext` (for implications, station requirements, worker skills) and filters everything to the specified skill. Output format follows the existing `displaySkillCtx` style but focused on one skill:

```
Skill 3: Grill
  Description: (none)
  Implies: Skill 1 (Prep)
  Implied by: Skill 5 (Management)
  Effective skills: Prep
  Workers: Worker 2 (Alice), Worker 4 (Bob)
  Required by stations: Station 1 (Grill Station)
  Cross-training: Worker 7 (Carol)
```

### 6. FK constraints — add REFERENCES to CREATE TABLE statements

Since existing databases can be dropped, modify the `CREATE TABLE IF NOT EXISTS` statements in `Schema.hs` directly. No migration needed.

Four tables gain FK references:

```sql
skill_implications:
  FOREIGN KEY (skill_id) REFERENCES skills(id)
  FOREIGN KEY (implies_skill_id) REFERENCES skills(id)

worker_skills:
  FOREIGN KEY (skill_id) REFERENCES skills(id)

station_required_skills:
  FOREIGN KEY (skill_id) REFERENCES skills(id)

worker_cross_training:
  FOREIGN KEY (skill_id) REFERENCES skills(id)
```

SQLite's default FK action is RESTRICT — attempting to delete a skill while references exist will raise an error. The app-level safe-delete check runs first and gives a better error message; the FK is a backstop.

### 7. `station remove-required-skill` follows existing patterns

New `Command` variant: `StationRemoveRequiredSkill Int Int` (station-id, skill-id).

Service layer: loads current required skills for the station, removes the specified skill from the set, calls `setStationRequiredSkills` with the updated set.

This mirrors how `station require-skill` works (load set, insert, save) but with `Set.delete` instead of `Set.insert`.

### 8. UI create skill flow

The "New Skill" button needs an ID and name. The simplest approach is a small inline form or modal. Since skill IDs are user-assigned (not auto-increment), the UI must prompt for both ID and name, matching the CLI `skill create <id> <name>` behavior.

The create request uses the existing `POST /api/skills` endpoint with `CreateSkillReq`.

## Risks / Trade-offs

**Force-delete partial failure** — If one sub-command fails mid-sequence, the skill is partially dereferenced. Each individual removal is idempotent and re-running force-delete will skip already-removed references and continue. The DB FK constraint prevents the final skill deletion from succeeding while any references remain, so we can't end up with a deleted skill that still has dangling references.

**`handleCommand` is IO, not Either** — Current command handlers print output and don't return success/failure. Force-delete can't easily detect if a sub-command failed. Mitigation: the sub-commands used (revoke-skill, remove-implication, clear-cross-training, remove-required-skill) are simple set-removal operations that shouldn't fail in practice. If the reference was already removed, the operation is a no-op.

**Breaking change to DELETE endpoint** — The existing `DELETE /api/skills/:id` changes from force-delete to safe-delete semantics. The only consumer is the web UI, updated in the same change.
