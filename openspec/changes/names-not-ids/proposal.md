# Proposal: Names, Not IDs

## Problem

Numeric IDs have leaked from the database into the user-facing command interface. This causes several problems:

- **Demo scripts and drafts use hardcoded IDs** that break when auto-increment sequences don't match expectations.
- **Some entities require the user to supply an ID at creation** (stations, absence types) — the system should assign IDs, not the user.
- **Commands are less readable**: `worker grant-skill 3 2` vs `worker grant-skill marco cooking`.
- **String is used where Text should be**, with pack/unpack conversions scattered at boundaries.

Skill has already been partially migrated by hand as a prototype for both changes (names-not-IDs and String-to-Text). The CLI and domain layers are done, but the UI still exposes IDs — the create form asks for an ID, routes use `/skills/:id`, and REST endpoints are ID-based. This proposal covers finishing the Skill prototype (UI + API) and then propagating the patterns to all remaining entities.

## Solution

Switch all entity commands from numeric IDs to unique names. Convert remaining String types to Data.Text. Use the Skill entity as the reference implementation.

### Core changes

1. **Commands accept names, not IDs.** Entity arguments in all commands become name-based. IDs are auto-assigned internally and never exposed to users.

2. **Names are unique per entity type.** Enforced at the database level. Names become the external key; IDs remain the internal key for joins and programmatic analysis.

3. **Audit log stores both.** Raw command (with names) in `aeCommand`. Resolved numeric IDs in `aeEntityId`/`aeTargetId`, populated at log time by the resolution layer. This supports programmatic analysis (draft rebasing) while keeping logs human-readable.

4. **String to Text.** All entity types, repository signatures, and supporting infrastructure migrate from String to Data.Text, following the pattern established in Skill.

5. **Replay always wipes.** Collapse `audit replay` and `audit demo` into a single `replay` command that resets the database before replaying. No name conflicts possible — commands are replayed in order against a virgin database.

6. **Name history derived from audit log.** No separate name history table. Rename events are traceable by scanning audit entries for a given entity ID with operation=rename. Only needed for draft rebasing, not replay.

7. **Hints render names at display time.** Hints keep IDs internally. Display names are looked up from the repository when rendering. Entity renames classified as Compatible in draft rebase — checkpoint advances, display updates automatically.

### Propagation order

**Wave 0 — Finish the Skill prototype:**
0. Skill UI + API — remove ID from create form, switch routes from `/skills/:id` to `/skills/:name`, switch REST endpoints from ID-based to name-based paths, implications keyed by name

**Wave 1 — Text only (no ID changes):**
1. Shift — already name-based, pure String-to-Text
2. Schedule — already name-based, pure String-to-Text

**Wave 2 — Text + ID removal:**
3. Station — user-specified ID becomes auto-assigned, name-based
4. Worker — domain types and repo signatures from Int/String to Text

**Wave 3 — Dependent entities:**
5. Absence Type — user-specified ID becomes auto-assigned, name-based
6. Absence — references Worker and Absence Type

**Wave 4 — Infrastructure:**
7. AuditEntry — String-to-Text for all fields
8. CommandMeta — String-to-Text for entity type constants, classify/render
9. Replay collapse — merge audit replay and demo into single wipe-and-replay command

### Layers touched per entity

Each entity migration touches five layers:
- **CLI** — command parsing and display
- **Domain** — type definitions
- **Repo** — Repository record signatures
- **SQLite** — persistence queries
- **UI** — React components, API client, REST endpoints, routes

## Not in scope

- Draft rebasing enhancements beyond rename classification — the existing rebase logic continues to work via resolved IDs in audit metadata.

## Risks

- **Cross-cutting scope**: touching all four layers for each entity makes individual changes larger. Mitigated by doing easy mechanical wins (Shift, Schedule) first.
- **Existing tests use hardcoded IDs**: test fixtures like `SkillId 1`, `WorkerId 2` will need to either capture IDs from creation or switch to name-based lookups. The Skill prototype shows the pattern.
