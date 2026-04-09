## Context

The calendar system (Change 1) stores accepted assignments in a continuous `calendar_assignments` table. The draft system (Change 2) introduces a draft-create/draft-commit workflow, and cross-draft validation (Change 3) ensures drafts don't conflict. However, there is currently no guardrail preventing a user from creating a draft that overwrites dates that have already passed. In a restaurant context, last week's schedule is history — editing it accidentally could corrupt records used for payroll or auditing.

The system uses a REPL-based CLI (`CLI/App.hs`) with session state tracked via `IORef`s in `AppState`. The `SessionContext` (in `CLI/Resolve.hs`) already tracks per-session entity references using an `IORef (Map EntityKind EntityRef)` pattern. The freeze line's temporary unfreezes fit naturally into this pattern as additional per-session state.

## Goals / Non-Goals

**Goals:**
- Warn users when a draft creation touches dates before the freeze line (default: yesterday)
- Provide an explicit `calendar unfreeze` command to temporarily allow edits to frozen dates
- Auto-refreeze after committing a draft that touched unfrozen historical dates
- Provide `calendar freeze-status` to show the current freeze line and any active unfreezes
- Keep unfreezes per-session (in-memory) so restarts restore the safety guardrail

**Non-Goals:**
- Hard locking of historical dates (the freeze line is advisory, not enforced at the database level)
- Persisted unfreeze state across sessions (per-session is simpler and safer)
- Configurable freeze line offset (always yesterday; a config option could be added later if needed)
- Freeze line awareness in non-draft flows (e.g., the legacy `schedule create` command is unaffected)

## Decisions

### Unfreezes are per-session, stored in an IORef alongside existing session state

The `AppState` record gains a new `IORef` holding a `Set (Day, Day)` representing temporarily unfrozen date ranges. This follows the same pattern as `asContext` and `asCheckpoints`.

**Alternative considered:** Persist unfreezes in a database table. Rejected because it adds schema complexity and undermines the safety model — if unfreezes survive restarts, a forgotten unfreeze could leave historical dates exposed indefinitely.

### Freeze line is computed, not stored

The freeze line is always yesterday (`addDays (-1) today`), computed fresh when needed. There is no stored "freeze line" value.

**Alternative considered:** Store the freeze line date in a config table so it can be adjusted. Rejected for now — the default of yesterday covers the use case, and a future change could add configurability if needed. Keeping it computed avoids schema changes.

### Freeze check happens at draft creation time, not at commit time

When a user creates a draft that covers a date range, the system checks whether any dates in that range fall before the freeze line. If so, it warns and asks for confirmation. The check is at creation time because that's when the user declares their intent — catching it early is better UX.

**Alternative considered:** Check at commit time. Rejected because by then the user has already done the work of editing the draft. Warning at creation and requiring explicit unfreeze is a better guardrail.

### The warning on draft create is a confirmation prompt, not a block

When a draft touches frozen dates and none of those dates have been explicitly unfrozen, the system prints a warning like:

```
WARNING: This draft covers dates before the freeze line (2026-04-07).
  Frozen dates in range: 2026-04-01 to 2026-04-07
  To edit historical dates, first run: calendar unfreeze 2026-04-01 2026-04-07
  Proceed anyway? (y/N)
```

Answering "y" creates the draft but does NOT unfreeze the dates — committing will still show a reminder. The explicit `calendar unfreeze` path is the intended workflow for intentional history edits.

**Alternative considered:** Block draft creation entirely until dates are unfrozen. Rejected because it's too rigid — sometimes you want to create a draft that happens to overlap the freeze line (e.g., a draft for "this week" where today is Wednesday and Mon/Tue are frozen).

### Unfreeze supports single date or date range

`calendar unfreeze <date>` unfreezes a single date. `calendar unfreeze <start> <end>` unfreezes an inclusive range. Both add to the set of unfrozen ranges in session state.

### Auto-refreeze clears all temporary unfreezes

When a draft is committed and any of its dates were in temporarily unfrozen ranges, the system clears ALL temporary unfreezes after the commit succeeds. This is simpler than tracking which unfreezes were "used" and ensures the session returns to a safe default state.

**Alternative considered:** Only clear unfreezes for the date range that was committed. Rejected because partial cleanup is error-prone and the user can always re-unfreeze if they have more historical edits to make.

### freeze-status shows both the freeze line date and active unfreezes

`calendar freeze-status` displays:
```
Freeze line: 2026-04-07 (yesterday)
Unfrozen ranges: 2026-04-01 to 2026-04-03
```

Or if no unfreezes are active:
```
Freeze line: 2026-04-07 (yesterday)
No temporary unfreezes active.
```

## Risks / Trade-offs

**[Risk] Freeze check only applies to draft creation, not legacy schedule commands** — The `schedule create` command bypasses the freeze line entirely since it predates the calendar/draft system.
→ Mitigation: This is acceptable. Legacy commands are already deprecated and will be removed. The freeze line is part of the new calendar workflow.

**[Risk] Per-session unfreezes lost on crash** — If the process crashes after unfreezing but before committing, the unfreeze is lost.
→ Mitigation: This is the desired behavior. The user must explicitly re-unfreeze, which is safer than leaving historical dates exposed.

**[Risk] Time zone edge cases for "yesterday"** — The freeze line computation uses the system's local date. In edge cases near midnight, "yesterday" might be surprising.
→ Mitigation: For a single-restaurant system, the server runs in the restaurant's time zone. This is sufficient for now. A future change could make the time zone configurable.

**[Risk] Drafts spanning the freeze boundary** — A draft for "this week" might include some frozen dates (past) and some unfrozen dates (future). The warning should clearly distinguish which dates are frozen.
→ Mitigation: The warning message lists the specific frozen dates in the range, not just the freeze line date.
