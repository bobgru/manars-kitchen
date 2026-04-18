# Proposal: Skill CRUD Completion

## Problem

Skills have create, list, rename, and info operations but are missing delete, view, and a UI creation flow. The existing `removeSkill` in the service layer does a bulk wipe without producing an audit trail of individual actions — so there's no path to an undo feature. Additionally, `SkillId` leaks as raw `Int` in the CLI commands, server API captures, and handlers, losing the type safety the newtype was designed to provide. The database schema declares no foreign key constraints on `skill_id`, so referential integrity is purely application-enforced.

## Solution

### 1. `skill delete` (safe delete)

Refuses to delete a skill that has any references. Checks all four tables:

| Table | Relationship |
|-------|-------------|
| `skill_implications` | skill_id or implies_skill_id |
| `worker_skills` | worker has this skill |
| `station_required_skills` | station requires this skill |
| `worker_cross_training` | worker is cross-training toward this skill |

Returns an error listing the references if any exist. The skill can only be deleted once all references have been manually removed.

### 2. `skill force-delete` (macro delete)

Expands to individual CLI commands dispatched through the full CLI pipeline (audit logging, SSE events). For a skill with references:

```
worker revoke-skill <worker> <skill>        (for each worker)
station remove-required-skill <station> <skill>  (for each station)
worker clear-cross-training <worker> <skill>     (for each cross-training goal)
skill remove-implication <a> <b>             (for each implication)
skill delete <skill>                         (final, now safe)
```

Each command produces its own audit log entry. A future undo feature can replay the complement of each command in reverse order:

```
skill create <id> <name>
skill implication <a> <b>
worker add-cross-training <worker> <skill>
station add-required-skill <station> <skill>
worker grant-skill <worker> <skill>
```

### 3. `skill view <id>`

Like `skill info` filtered for a single skill. Shows:

- Skill name and description
- Workers who have this skill
- Stations that require this skill
- Direct implications (what it implies and what implies it)
- Transitive (effective) implications
- Cross-training goals targeting this skill

### 4. UI: create button and delete button

**Skills list page** gets:

- A "New Skill" button that creates a skill
- A "Delete" button on each skill row

**Delete flow:**

```
User clicks [Delete]
  -> API: DELETE /api/skills/:id          (safe delete attempt)
  -> 200: deleted, UI refreshes
     OR
  -> 409 Conflict with reference summary
  -> UI shows confirmation dialog:
     "Grill" is in use:
       - 2 workers: Alice, Bob
       - 1 station: Grill Station
       - 1 implication: implies Prep
     [Cancel]  [Force Delete]
  -> If confirmed: DELETE /api/skills/:id/force
```

### 5. `SkillId` type propagation

Replace raw `Int` with `SkillId` in:

- `Commands.hs` ADT variants and parser
- `Server/Api.hs` Capture types
- `Server/Handlers.hs` handler parameters

Requires adding `FromHttpApiData` / `ToHttpApiData` instances for `SkillId`. This establishes the pattern for propagating type-safe IDs to other entities later.

### 6. Foreign key constraints for `skill_id`

Add `REFERENCES skills(id)` to the four referencing tables in `Schema.hs`:

```sql
skill_implications     (skill_id, implies_skill_id -> skills(id))
worker_skills          (skill_id -> skills(id))
station_required_skills (skill_id -> skills(id))
worker_cross_training   (skill_id -> skills(id))
```

Default SQLite behavior (RESTRICT) prevents deletion while references exist, acting as a safety net behind the application-level checks. Since this is early development with no users, existing databases can be dropped and recreated.

FK constraints are scoped to `skill_id` only. Other entities (stations, workers, shifts, users) have incomplete reference cleanup in their delete paths and would cause SQL exceptions with FK enforcement. Those will be addressed when each entity gets the delete/force-delete pattern.

### 8. Add `station remove-required-skill` command

`station require-skill <station> <skill>` exists but there is no inverse. Force-delete needs to dispatch individual removal commands, so `station remove-required-skill <station> <skill>` must be added. This follows the same pattern as `worker revoke-skill` and `worker clear-cross-training` which already exist.

### 9. Add `skill rename` to help text

`skill rename <id> <name>` is fully implemented but missing from the help text. Add it alongside the new commands so the full skill command set is discoverable.

### 7. Bug fix: `sqlDeleteSkill` missing `worker_cross_training`

The existing `sqlDeleteSkill` (SQLite.hs:190-195) deletes from `skill_implications`, `worker_skills`, and `station_required_skills` but does not delete from `worker_cross_training`. This will be fixed as part of the force-delete implementation.

## Not in scope

- Delete/force-delete for other entities (stations, workers, shifts, users)
- FK constraints for non-skill foreign keys
- Undo/redo feature (this change lays the groundwork by ensuring audit trail granularity)
- Skill description editing in the UI

## Risks

- **Force-delete atomicity**: The macro dispatches multiple commands. If one fails mid-way, the skill is partially dereferenced. Mitigation: each individual command is idempotent and the user can re-run force-delete to finish.
- **Full CLI dispatch overhead**: Force-delete goes through the complete command pipeline for each reference removal. This is deliberate (audit trail for undo) but slower than a bulk SQL delete. Acceptable for the expected scale.
