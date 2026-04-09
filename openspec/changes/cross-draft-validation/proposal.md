## Why

When concurrent drafts exist (e.g., this-month and next-month), accepting changes to one draft can invalidate assignments in another. For example, committing a calendar change where Marco works the Apr 26-27 weekend means his May 3-4 weekend assignment in a next-month draft now violates the alternating-weekends rule. Without automatic detection, these violations silently persist until someone notices a constraint breach in the published schedule. This is Change 3 of 7, building on the draft system (Change 2) and calendar foundation (Change 1).

## What Changes

- **Validation on draft open**: When a user opens a draft, the system detects whether the calendar has changed since the draft was created by checking calendar commit timestamps against the draft's creation time.
- **Hard constraint re-validation**: If the calendar changed, all assignments in the draft are re-validated against hard constraints using the current calendar for look-back context (e.g., loading the last week of calendar before the draft's start date to populate previous-weekend workers, check rest periods, etc.).
- **Auto-removal of violations**: Assignments that now violate hard constraints are automatically removed from the draft. Hard constraints checked: alternating weekends, skill qualification, absence conflicts, weekly hour limits, daily hour limits, rest periods, consecutive hours, and avoid-pairing.
- **Violation reporting**: Removed assignments are reported to the user with specific reasons (e.g., "Marco: worked Apr 26-27 (new), was scheduled May 3-4 -> violates alternating weekends -> removed from May 3 grill, May 4 grill").
- **Diagnose suggestion**: After reporting removals, the system suggests running `diagnose` to identify how to fill the resulting gaps.

## Capabilities

### New Capabilities
- `draft-validation`: Re-validate a draft's assignments against hard constraints on open, using current calendar state for look-back context. Auto-remove violating assignments and report removals with reasons.

### Modified Capabilities

## Impact

- **Service layer**: New validation function (e.g., `validateDraftAgainstCalendar`) in `Service/Draft.hs` (the draft service module introduced by Change 2). Loads calendar look-back context and re-checks each assignment against hard constraints.
- **Domain layer**: No new constraint logic needed. Reuses existing `canAssignSlot` from `Domain/Scheduler.hs` and individual constraint checks from `Domain/Worker.hs`. The key integration point is populating `SchedulerContext.schPrevWeekendWorkers` from calendar data.
- **Repository layer**: Needs to query calendar commits by timestamp to detect changes since draft creation. May need a thin query function if not already provided by Change 1's `repoListCommits`.
- **CLI layer**: The draft-open command handler gains a validation step. Display logic for violation reports (worker name, reason, removed assignments).
- **No breaking changes**. This is purely additive behavior on an existing flow.
