## 1. SkillId Type Propagation

- [x] 1.1 Add `FromHttpApiData` and `ToHttpApiData` instances for `SkillId` in `Domain/Types.hs` (add `web-http-api-data` dependency if needed)
- [x] 1.2 Change `Command` ADT variants in `Commands.hs` to use `SkillId` instead of `Int` for skill parameters: `SkillCreate`, `SkillRename`, `SkillImplication`, `SkillRemoveImplication`, `StationRequireSkill` (skill param), `WorkerGrantSkill` (skill param), `WorkerRevokeSkill` (skill param), `WorkerSetCrossTraining` (skill param), `WorkerClearCrossTraining` (skill param)
- [x] 1.3 Update `parseCommand` in `Commands.hs` to wrap parsed skill IDs in `SkillId`
- [x] 1.4 Update all `handleCommand` cases in `App.hs` to pattern-match `SkillId` instead of wrapping raw `Int`
- [x] 1.5 Change `Capture "id" Int` to `Capture "id" SkillId` in skill routes in `Server/Api.hs`
- [x] 1.6 Update skill handler functions in `Server/Handlers.hs` to accept `SkillId` parameters, removing manual `SkillId` wrapping
- [x] 1.7 Verify the project compiles and tests pass with all SkillId changes

## 2. FK Constraints and Bug Fix

- [x] 2.1 Add `REFERENCES skills(id)` to `skill_implications` (both columns), `worker_skills`, `station_required_skills`, and `worker_cross_training` in `Schema.hs`
- [x] 2.2 Add `worker_cross_training` cleanup to `sqlDeleteSkill` in `SQLite.hs`
- [x] 2.3 Drop and recreate test database(s) to pick up new FK constraints
- [x] 2.4 Verify FK constraints work: test that inserting a row with a nonexistent skill_id fails

## 3. Service Layer: Reference Checking

- [x] 3.1 Add `SkillReferences` data type to `Service/Worker.hs` (or a new module) with fields for workers, stations, cross-training, implied-by, and implies
- [x] 3.2 Implement `checkSkillReferences :: Repository -> SkillId -> IO SkillReferences` that queries all four reference tables
- [x] 3.3 Add `isUnreferenced :: SkillReferences -> Bool` helper
- [x] 3.4 Implement `safeDeleteSkill :: Repository -> SkillId -> IO (Either SkillReferences ())` that checks references first, only deletes if unreferenced

## 4. `station remove-required-skill` Command

- [x] 4.1 Add `StationRemoveRequiredSkill` variant to `Command` ADT in `Commands.hs`
- [x] 4.2 Add parser for `station remove-required-skill <station> <skill>` in `Commands.hs`
- [x] 4.3 Add `handleCommand` case in `App.hs`: load station's required skills, remove the specified skill, save updated set
- [x] 4.4 Add to `isMutating` in `App.hs`
- [x] 4.5 Add to help text in `App.hs`
- [x] 4.6 Add to entity resolution in `Resolve.hs`
- [x] 4.7 Add to `CommandMeta` audit classification

## 5. `skill delete` and `skill force-delete` CLI Commands

- [x] 5.1 Add `SkillDelete` and `SkillForceDelete` variants to `Command` ADT in `Commands.hs`
- [x] 5.2 Add parsers for `skill delete <id>` and `skill force-delete <id>` in `Commands.hs`
- [x] 5.3 Implement `skill delete` handler in `App.hs`: call `safeDeleteSkill`, print references on failure
- [x] 5.4 Implement `skill force-delete` handler in `App.hs`: call `checkSkillReferences`, build list of `Command` values for each reference, dispatch each through `handleCommand`, then dispatch `SkillDelete`
- [x] 5.5 Add both to `isMutating` in `App.hs`
- [x] 5.6 Add both to help text in `App.hs`
- [x] 5.7 Add to entity resolution in `Resolve.hs`
- [x] 5.8 Add to `CommandMeta` audit classification

## 6. `skill view` CLI Command

- [x] 6.1 Add `SkillView` variant to `Command` ADT in `Commands.hs`
- [x] 6.2 Add parser for `skill view <id>` in `Commands.hs`
- [x] 6.3 Implement `skill view` handler in `App.hs`: load SkillContext, filter to specified skill, display name, description, implications (both directions), effective skills, workers, stations, cross-training
- [x] 6.4 Add display function in `Display.hs` for single-skill view
- [x] 6.5 Add to help text in `App.hs`
- [x] 6.6 Add to entity resolution in `Resolve.hs`

## 7. `skill rename` Help Text

- [x] 7.1 Add `skill rename <id> <name>` to skill help entries in `App.hs`

## 8. Server API: Safe Delete and Force Delete Endpoints

- [x] 8.1 Add `ToJSON` instance for `SkillReferences` (for 409 response body)
- [x] 8.2 Change `handleDeleteSkill` to use `safeDeleteSkill`, returning 409 with references on conflict
- [x] 8.3 Add `handleForceDeleteSkill` handler that dispatches individual commands via the command pipeline
- [x] 8.4 Add `DELETE /api/skills/:id/force` route to `Server/Api.hs`
- [x] 8.5 Wire `handleForceDeleteSkill` into the server in `Server/App.hs` (or wherever handlers are composed)

## 9. UI: Create Skill Button

- [x] 9.1 Add `createSkill` function to `web/src/api/skills.ts` calling `POST /api/skills`
- [x] 9.2 Add "New Skill" button with inline form (ID + name fields) to `SkillsListPage.tsx`
- [x] 9.3 Handle success (refresh list) and error (show conflict message)

## 10. UI: Delete Skill Button

- [x] 10.1 Add `deleteSkill` and `forceDeleteSkill` functions to `web/src/api/skills.ts`
- [x] 10.2 Add "Delete" button to each skill row in `SkillsListPage.tsx`
- [x] 10.3 Implement delete flow: call safe delete, on 409 show confirmation dialog with reference summary
- [x] 10.4 Implement confirmation dialog with "Cancel" and "Force Delete" buttons
- [x] 10.5 Handle force-delete response (refresh list on success, show error on failure)

## 11. Verification

- [x] 11.1 Run `stack clean && stack build` and fix all warnings
- [x] 11.2 Run `stack test` and verify all tests pass
- [x] 11.3 Test demo script still works end to end
- [x] 11.4 Manual test in browser: create skill, view skills list, delete unreferenced skill, attempt delete of referenced skill, force-delete referenced skill
