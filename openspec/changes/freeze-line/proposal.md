## Why

The continuous calendar (Change 1) accumulates accepted assignments over time. With the draft system (Change 2) and cross-draft validation (Change 3), users can create and commit drafts that overwrite date ranges. However, nothing prevents accidentally editing dates that have already passed — a user could inadvertently overwrite last week's schedule without realizing it. A freeze line provides a lightweight guardrail that warns before editing historical dates, while still allowing intentional history rewrites (e.g., recording after-the-fact changes like reassigning a junior worker for training purposes).

## What Changes

- **New concept: freeze line** — a date boundary (default: yesterday) below which calendar dates are considered frozen. Dates before the freeze line require explicit unfreezing before they can be edited via drafts.
- **Draft creation warning** — when creating a draft that touches dates before the freeze line, the system warns and asks for confirmation before proceeding.
- **Explicit unfreeze commands** — `calendar unfreeze <date>` or `calendar unfreeze <start> <end>` temporarily moves the freeze line back for the current session, allowing edits to those historical dates.
- **Freeze status command** — `calendar freeze-status` displays the current freeze line and any temporary unfreezes in the active session.
- **Auto-refreeze on commit** — after committing a draft that touched unfrozen historical dates, all temporary unfreezes are cleared and the freeze line returns to its default (yesterday).
- The freeze line is a **policy guardrail**, not a hard lock — it prevents accidental history edits, not intentional ones.
- Default is **yesterday** (not today) because today's schedule might still need end-of-day adjustments.

## Capabilities

### New Capabilities
- `freeze-line`: Freeze/unfreeze guardrail for historical calendar dates. Includes freeze line computation, unfreeze commands, freeze status display, and auto-refreeze on commit. Unfreezes are per-session (in-memory, lost on restart) for simplicity and safety.

### Modified Capabilities
- `session-context`: Session state gains freeze-related fields — the set of temporarily unfrozen date ranges is tracked in the session for the duration of the process.

## Impact

- **CLI**: New commands `calendar unfreeze` and `calendar freeze-status` added to the calendar command group. Draft creation flow gains a freeze-line check and confirmation prompt.
- **Service layer**: Draft creation in the service layer gains freeze-line awareness — checking whether proposed dates fall before the freeze line and whether they have been explicitly unfrozen. Commit flow gains auto-refreeze logic.
- **Session/state**: In-memory session state extended to track temporary unfreezes (set of date ranges). No new database tables needed — the freeze line is computed as yesterday, and unfreezes are ephemeral.
- **Domain**: No changes to domain types or the scheduler algorithm.
