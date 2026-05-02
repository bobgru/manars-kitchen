# Tasks: Names, Not IDs

## Wave 0: Finish Skill prototype

- [x] 0.1. **REST endpoints: SkillId → name** — In `server/Server/Api.hs`, change all `Capture "id" SkillId` to `Capture "name" Text`. Update `Handlers.hs` to resolve name → SkillId before calling service functions. Add `repoGetSkillByName` or use existing list + filter.
- [x] 0.2. **REST response: drop IDs** — Change `GET /api/skills` to return `[Skill]` (name + description) instead of `[(SkillId, Skill)]`. Change `GET /api/skills/implications` to return `Record<name, name[]>` instead of `Record<id, id[]>`.
- [x] 0.3. **JSON types: remove ID from create** — In `server/Server/Json.hs`, verify `CreateSkillReq` has no ID field (already the case). Update any response types that expose SkillId.
- [x] 0.4. **UI API client** — In `web/src/api/skills.ts`, change `SkillInfo` to drop `id: number`. All functions take/return names. `fetchImplications` returns `Record<string, string[]>`.
- [x] 0.5. **UI create form** — In `SkillsListPage.tsx`, remove ID input field (`newId` state, `<input type="number">`). `createSkill` takes name only.
- [x] 0.6. **UI routing** — In `App.tsx`, change route from `skills/:id` to `skills/:name`. In `SkillsListPage.tsx`, change Link to `/skills/${s.name}`. In `SkillDetailPage.tsx`, use `useParams<{ name: string }>`.
- [x] 0.7. **UI implications** — In both skill pages, change implication tracking from `Record<number, number[]>` to `Record<string, string[]>`. Transitive closure keyed by name.
- [x] 0.8. **Demo script: skills** — In `demo/restaurant-setup.txt`, change `skill create 1 grill` to `skill create grill`. Change `skill implication 8 1` to `skill implication master-chef grill`. All skill references by name.
- [x] 0.9. **Build and test** — `stack clean && stack build && stack test`. `cd web && npm run build`. Fix all warnings. Run demo (`make fast-demo`). Verify skill pages in browser.

## Wave 1: Shift — String to Text

- [x] 1.1. **Domain type** — In `Domain/Shift.hs`, change `sdName :: !String` to `sdName :: !Text`. Add `Data.Text` import.
- [x] 1.2. **Repo signatures** — In `Repo/Types.hs`, change `repoDeleteShift :: String -> IO ()` to `Text`. Any other shift-related String signatures.
- [x] 1.3. **SQLite implementation** — In `Repo/SQLite.hs`, update shift queries to use Text. Pack/unpack at SQLite boundary as needed.
- [x] 1.4. **CLI layer** — In `CLI/Commands.hs` and `CLI/App.hs`, pack String input from parser to Text at the command boundary. Update display code.
- [x] 1.5. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 1: Schedule — String to Text

- [x] 1.6. **Repo signatures** — In `Repo/Types.hs`, change all schedule functions from String to Text: `repoSaveSchedule`, `repoLoadSchedule`, `repoListSchedules`, `repoDeleteSchedule`.
- [x] 1.7. **SQLite implementation** — In `Repo/SQLite.hs`, update schedule queries to use Text.
- [x] 1.8. **CLI layer** — In `CLI/Commands.hs` and `CLI/App.hs`, pack String input to Text at command boundary. Update display and any schedule name handling.
- [x] 1.9. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 2: Station — Text + ID removal

- [x] 2.1. **SQLite schema** — Change `stations.id` to `INTEGER PRIMARY KEY AUTOINCREMENT`. Add `UNIQUE` constraint on station name.
- [x] 2.2. **Repo signatures** — Change `repoCreateStation :: StationId -> String -> IO ()` to `repoCreateStation :: Text -> IO ()`. Change `repoListStations :: IO [(StationId, String)]` to `IO [(StationId, Text)]`. All station String → Text.
- [x] 2.3. **SQLite implementation** — Update station queries. Creation no longer takes an ID. Add name lookup for resolution.
- [x] 2.4. **CLI commands** — Change `StationAdd Int String` to `StationAdd String` (name only). All station commands that take `StationId` argument: update parsing in `Commands.hs` to take name (resolved by `Resolve.hs`).
- [x] 2.5. **CLI handlers** — Update station command handlers in `App.hs` to work with name-based resolution.
- [x] 2.6. **Demo script: stations** — Change `station add 1 grill` to `station add grill`. Change `station require-skill 1 1` to `station require-skill grill grill`. All station references by name.
- [x] 2.7. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 2: Worker — Text + ID cleanup

- [x] 2.8. **Domain types** — In `Domain/Worker.hs`, change `wcShiftPrefs :: !(Map WorkerId [String])` to `[Text]`. Any other String fields.
- [x] 2.9. **Repo signatures** — In `Repo/Types.hs`, change worker-related String signatures to Text. `repoCreateUser`, `repoGetUserByName`, `repoUpdatePassword`, etc.
- [x] 2.10. **SQLite implementation** — Update worker/user queries to use Text.
- [x] 2.11. **CLI layer** — Update worker command parsing and display to use Text. Ensure WorkerId is never displayed to users.
- [x] 2.12. **Demo script: workers** — Change any numeric worker references to usernames: `worker grant-skill 1 8` to `worker grant-skill marco master-chef`. All worker references by name.
- [x] 2.13. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 3: Absence Type — Text + ID removal

- [x] 3.1. **Repo signatures** — Change `repoCreateAbsenceType` to take name only (Text), return auto-assigned ID. All absence type String → Text.
- [x] 3.2. **SQLite schema + implementation** — Auto-increment for absence type ID. Unique name constraint. Update queries.
- [x] 3.3. **CLI commands** — Change absence type commands from user-supplied ID to name-only creation. Update parsing and resolution.
- [x] 3.4. **Demo script: absence types** — Update to name-based references.
- [x] 3.5. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 3: Absence — Text migration

- [x] 3.6. **CLI commands** — Update absence commands to reference workers and absence types by name. Update parsing.
- [x] 3.7. **Repo/SQLite** — String → Text for absence-related signatures and queries.
- [x] 3.8. **Demo script: absences** — Update to name-based references.
- [x] 3.9. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 4: AuditEntry — String to Text

- [x] 4.1. **AuditEntry type** — In `Repo/Types.hs`, change all String fields to Text: `aeTimestamp`, `aeUsername`, `aeCommand`, `aeEntityType`, `aeOperation`, `aeDateFrom`, `aeDateTo`, `aeParams`, `aeSource`.
- [x] 4.2. **SQLite implementation** — Update audit log queries in `Repo/SQLite.hs` to produce/consume Text.
- [x] 4.3. **All AuditEntry consumers** — Update `CLI/App.hs` (replay, display), `Service/HintRebase.hs`, and any other modules that read AuditEntry fields.
- [x] 4.4. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 4: CommandMeta — String to Text

- [x] 4.5. **CommandMeta type** — In `Audit/CommandMeta.hs`, change all String fields and entity type constants to Text. `classify` and `render` operate on Text.
- [x] 4.6. **All CommandMeta consumers** — Update `HintRebase.hs`, `App.hs`, `Handlers.hs`, `PubSub.hs`, and any other modules that use CommandMeta or entity type constants.
- [x] 4.7. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.

## Wave 4: Replay collapse

- [x] 4.8. **Merge replay commands** — Collapse `CmdReplay`, `CmdReplayFile`, and `CmdDemo` into a single `Replay` command that always wipes, bootstraps, and replays.
- [x] 4.9. **Update command parsing** — In `Commands.hs`, single `replay` command (optionally takes a file path). Remove `audit replay`, `audit demo` as separate commands.
- [x] 4.10. **Update help text** — Remove old audit replay/demo entries, add new replay command.
- [x] 4.11. **Audit log: resolved IDs** — Ensure the logging path (pub/sub or direct) stores resolved entity IDs in `entity_id`/`target_id` columns. The resolution layer provides these; `classify` no longer needs to parse them from the raw command string.
- [x] 4.12. **HintRebase: rename as Compatible** — In `Service/HintRebase.hs`, classify entity rename operations as `Compatible` (not `Irrelevant`). Optionally emit a message noting the rename.
- [x] 4.13. **Build and test** — `stack clean && stack build && stack test`. Fix all warnings. Run demo.
