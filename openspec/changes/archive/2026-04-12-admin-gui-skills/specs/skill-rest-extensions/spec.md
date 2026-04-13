# Spec: Skill REST Extensions

## Overview

Add three new backend capabilities for skills: rename, read implications, and mutate implications. These are exposed as REST endpoints and backed by new repository and service functions.

## Requirements

### R1: Rename skill

- `PUT /api/skills/:id` with body `{ "name": "<new name>" }` renames a skill.
- Returns 204 on success.
- Returns 404 if the skill ID does not exist.
- Requires admin auth.
- Repository: add `repoRenameSkill :: SkillId -> String -> IO ()` to the Repository record.
- SQLite: `UPDATE skills SET name = ? WHERE id = ?`.
- Service: `renameSkill :: Repository -> SkillId -> String -> IO ()` in Service.Worker.

### R2: List skill implications

- `GET /api/skills/implications` returns all direct implications.
- Response is a JSON object mapping skill ID (as string key) to an array of implied skill IDs:
  ```json
  { "1": [2], "3": [1] }
  ```
- Skills with no implications are omitted from the map.
- Requires auth (any role).
- Repository: add `repoListSkillImplications :: IO [(SkillId, SkillId)]` — returns all `(skill_id, implies_skill_id)` pairs from the `skill_implications` table.
- Service: `listSkillImplications :: Repository -> IO (Map SkillId [SkillId])` groups the pairs into a map.

### R3: Add skill implication

- `POST /api/skills/:id/implications` with body `{ "impliesSkillId": N }` adds a direct implication.
- Returns 204 on success.
- Idempotent: adding an existing implication is a no-op.
- Requires admin auth.
- Delegates to existing `addSkillImplication` in Service.Worker.

### R4: Remove skill implication

- `DELETE /api/skills/:id/implications/:impliedId` removes a direct implication.
- Returns 204 on success.
- Idempotent: removing a nonexistent implication is a no-op.
- Requires admin auth.
- Repository: add `repoRemoveSkillImplication :: SkillId -> SkillId -> IO ()`.
- SQLite: `DELETE FROM skill_implications WHERE skill_id = ? AND implies_skill_id = ?`.
- Service: `removeSkillImplication :: Repository -> SkillId -> SkillId -> IO ()` in Service.Worker.

## JSON types

### RenameSkillReq

```json
{ "name": "New Skill Name" }
```

### AddImplicationReq

```json
{ "impliesSkillId": 2 }
```

### Implications response

```json
{ "1": [2], "3": [1] }
```

## Files to modify

| File | Changes |
|------|---------|
| `src/Repo/Types.hs` | Add `repoRenameSkill`, `repoListSkillImplications`, `repoRemoveSkillImplication` to Repository record |
| `src/Repo/SQLite.hs` | Implement `sqlRenameSkill`, `sqlListSkillImplications`, `sqlRemoveSkillImplication`; wire into `newSQLiteRepo` |
| `src/Service/Worker.hs` | Add `renameSkill`, `removeSkillImplication`, `listSkillImplications`; export them |
| `server/Server/Api.hs` | Add 4 new endpoint types to `RawAPI` |
| `server/Server/Json.hs` | Add `RenameSkillReq`, `AddImplicationReq` types with JSON instances |
| `server/Server/Handlers.hs` | Add `handleRenameSkill`, `handleListImplications`, `handleAddImplication`, `handleRemoveImplication` |
