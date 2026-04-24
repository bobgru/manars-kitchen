# Design: Names, Not IDs

## Architecture

The change removes numeric IDs from all user-facing interfaces (CLI commands, REST endpoints, UI) and replaces them with unique names. IDs remain as internal keys for joins and programmatic analysis.

```
User-facing                    Boundary                      Internal
──────────                     ────────                      ────────
CLI: "skill rename grill X"   Resolve: "grill" → SkillId 1  Domain uses SkillId
REST: PUT /api/skills/grill    Lookup: "grill" → SkillId 1   Repo uses SkillId
UI: /skills/grill              API returns name, maps by name SQLite joins by id
```

### Resolution boundary

Today, name → ID resolution happens in `CLI/Resolve.hs` before command execution. After this change, the same boundary exists but shifts from "convenience" to "required". The REST layer gets an equivalent: path parameters become names, handlers resolve to IDs before calling the service layer.

```
CLI path:    raw command → Resolve.hs → Command (with IDs) → handleCommand
REST path:   /api/skills/:name → Handler (resolve name) → Service (with IDs)
UI path:     /skills/:name → fetch /api/skills/:name → display
```

## Wave 0: Finish Skill prototype

Skill CLI and domain already use names + Text. The UI and REST API still use numeric IDs.

### REST endpoint changes

| Before | After |
|--------|-------|
| `DELETE /api/skills/:id` | `DELETE /api/skills/:name` |
| `DELETE /api/skills/:id/force` | `DELETE /api/skills/:name/force` |
| `PUT /api/skills/:id` | `PUT /api/skills/:name` |
| `POST /api/skills/:id/implications` | `POST /api/skills/:name/implications` |
| `DELETE /api/skills/:id/implications/:impliedId` | `DELETE /api/skills/:name/implications/:impliedName` |

`GET /api/skills` returns skill objects without exposing IDs:

```json
[{"name": "grill", "description": ""}, {"name": "pizza", "description": ""}]
```

`GET /api/skills/implications` returns names instead of IDs:

```json
{"grill": ["beverage", "busboy"], "master-chef": ["grill", "pizza", ...]}
```

### Servant API type changes

Replace `Capture "id" SkillId` with `Capture "name" Text`. Handlers resolve the name to a `SkillId` via `repoListSkills` or a new `repoGetSkillByName` repo function.

### UI changes

- **Create form**: remove ID input; user provides name only
- **Routes**: `/skills/:id` becomes `/skills/:name`
- **SkillDetailPage**: `useParams<{ name: string }>` instead of `{ id: string }`
- **API client** (`api/skills.ts`): all functions take/return names, no numeric IDs
- **Implications**: `Record<string, string[]>` keyed by name

### Demo script

```
# Before                    # After
skill create 1 grill        skill create grill
skill create 2 pizza         skill create pizza
skill implication 8 1        skill implication master-chef grill
```

### Command type (already done in CLI)

`SkillCreate` already takes name only. `SkillRename`, `SkillDelete`, etc. take `SkillId` in the Command type, but `Resolve.hs` resolves names before constructing these. No change needed in Command types — the resolution layer handles it.

## Wave 1: Shift and Schedule (String → Text)

These entities are already name-based. Only String → Text migration needed.

### Shift

```haskell
-- Before (Domain/Shift.hs)
data ShiftDef = ShiftDef
    { sdName  :: !String
    , sdStart :: !Int
    , sdEnd   :: !Int
    }

-- After
data ShiftDef = ShiftDef
    { sdName  :: !Text
    , sdStart :: !Int
    , sdEnd   :: !Int
    }
```

Repository signatures change:
```haskell
-- Before
, repoDeleteShift :: String -> IO ()
-- After
, repoDeleteShift :: Text -> IO ()
```

All callers in `App.hs`, `Commands.hs`, `SQLite.hs` switch from String to Text (pack at CLI boundary).

### Schedule

Repository signatures change:
```haskell
-- Before
, repoSaveSchedule   :: String -> Schedule -> IO ()
, repoLoadSchedule   :: String -> IO (Maybe Schedule)
, repoListSchedules  :: IO [String]
, repoDeleteSchedule :: String -> IO ()

-- After (all String → Text)
, repoSaveSchedule   :: Text -> Schedule -> IO ()
, repoLoadSchedule   :: Text -> IO (Maybe Schedule)
, repoListSchedules  :: IO [Text]
, repoDeleteSchedule :: Text -> IO ()
```

## Wave 2: Station and Worker (Text + ID removal)

### Station

Stations currently require user-specified IDs at creation: `station add 1 grill`. After the change: `station add grill`.

```haskell
-- Before (Repo/Types.hs)
, repoCreateStation  :: StationId -> String -> IO ()
, repoListStations   :: IO [(StationId, String)]

-- After
, repoCreateStation  :: Text -> IO ()
, repoListStations   :: IO [(StationId, Text)]
```

SQLite schema change: `stations.id` becomes `INTEGER PRIMARY KEY AUTOINCREMENT` instead of user-supplied.

All station commands switch from `StationId` argument to name resolution:
```
# Before                        # After
station add 1 grill              station add grill
station set-hours 1 8 17         station set-hours grill 8 17
station require-skill 1 2        station require-skill grill pizza
```

### Worker

Workers are already created by username and resolved by username via `Resolve.hs`. The main change is String → Text in domain types and repo signatures, plus ensuring the `WorkerId` is never shown to users.

```haskell
-- WorkerContext fields: String → Text where applicable
, wcShiftPrefs :: !(Map WorkerId [Text])   -- was [String]
```

Commands already accept names via resolution. The display layer stops showing `WorkerId` values.

## Wave 3: Absence Type and Absence

### Absence Type

Currently: `absence-type create 1 vacation`. After: `absence-type create vacation`.

```haskell
-- Before
, repoCreateAbsenceType :: AbsenceTypeId -> String -> IO ()
-- After  
, repoCreateAbsenceType :: Text -> IO (AbsenceTypeId)
```

Same pattern as Station: remove user-supplied ID, auto-assign, reference by name.

### Absence

Absence commands reference workers and absence types by name:
```
# Before                                    # After
absence set-allowance 1 1 10                absence set-allowance marco vacation 10
absence request 1 2 2026-05-01 2026-05-05   absence request vacation marco 2026-05-01 2026-05-05
```

## Wave 4: Infrastructure

### AuditEntry (String → Text)

```haskell
-- Before
data AuditEntry = AuditEntry
    { aeId        :: !Int
    , aeTimestamp  :: !String
    , aeUsername   :: !String
    , aeCommand    :: !(Maybe String)
    ...

-- After
data AuditEntry = AuditEntry
    { aeId        :: !Int
    , aeTimestamp  :: !Text
    , aeUsername   :: !Text
    , aeCommand    :: !(Maybe Text)
    ...
```

### CommandMeta (String → Text)

Entity type constants become Text:
```haskell
-- Before
etWorker, etStation, etSkill :: String
-- After
etWorker, etStation, etSkill :: Text
```

`classify` and `render` operate on Text. `readMaybe` for ID extraction stays numeric (parsing entity IDs from audit log commands for structured metadata).

### Audit log: resolved IDs

The `repoLogCommand` / `repoLogCommandWithSource` functions (or their pub/sub replacements) receive the resolved IDs from the resolution layer and store them in `entity_id` / `target_id` columns. Today `classify` parses these from the raw command string; after the change, the caller provides them since command arguments are names, not parseable IDs.

### Replay collapse

Merge `CmdReplay`, `CmdReplayFile`, and `CmdDemo` into a single `Replay` command that always:
1. Wipes the database
2. Bootstraps admin user
3. Replays commands sequentially

The `replayCommands` function stays largely the same. Error handling: warn and continue (Option B).

## Key decisions

### Names are the external key, IDs are the internal key

Users never see or type IDs. All command arguments, REST paths, UI routes, and display use names. IDs exist in the database for joins, in the audit log for programmatic analysis, and in domain types for efficient lookups.

### Audit log stores resolved IDs at log time

When a command is logged, the resolution layer has already mapped names to IDs. Both the raw command (human-readable, with names) and the resolved IDs (structured metadata) are stored. This supports draft rebasing without needing to re-resolve names (which may have changed since the command was logged).

### Name history derived from audit log

No separate `name_history` table. To trace an entity's name changes, scan audit entries for `(entity_type=X, entity_id=N, operation=rename)`. The raw command contains both old and new names.

### Hints use IDs, display uses names

Hints (what-if scenarios) continue to reference entities by ID internally. When rendering hints for the user, current names are looked up from the repository. Entity renames are classified as `Compatible` in draft rebase — the checkpoint advances and display names update automatically on next render.

### Replay always starts from clean database

No need for name conflict resolution, history lookups, or stale-ID detection during replay. Commands are the source of truth, replayed in order against a virgin database.
