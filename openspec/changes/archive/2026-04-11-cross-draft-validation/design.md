## Context

The system (after Changes 1-2) has a continuous calendar and a draft system supporting concurrent drafts. A typical workflow has two drafts open simultaneously: this-month (being refined) and next-month (being built). When this-month is finalized and committed to the calendar, the calendar state changes. Next-month's draft, created earlier, may now contain assignments that violate hard constraints because the look-back context has shifted.

The scheduler already has all the hard constraint checks in `Domain/Scheduler.hs` (`canAssignSlot`) and `Domain/Worker.hs` (individual checks like `blockedByAlternateWeekend`, `violatesRestPeriod`, `needsBreak`, `wouldBeOvertime`, `wouldExceedDailyRegular`, `workerAvoidsAt`). The `SchedulerContext` type carries all context needed for these checks, including `schPrevWeekendWorkers` for the alternating-weekends rule.

The calendar history system (Change 1) records commits with timestamps, and the draft system (Change 2) records draft creation times. These two timestamps are the basis for detecting whether a draft needs re-validation.

## Goals / Non-Goals

**Goals:**
- Detect when a draft's assumptions about the calendar are stale (calendar changed since draft creation)
- Re-validate every assignment in the draft against hard constraints using the current calendar for look-back context
- Automatically remove assignments that violate hard constraints
- Report each removal with a human-readable explanation (worker, what changed, which constraint, what was removed)
- Guide the user to fill gaps via `diagnose`

**Non-Goals:**
- Soft constraint re-evaluation (preferences, scoring) — drafts may become suboptimal but not invalid
- Automatic re-scheduling to fill gaps left by removals (user decides, or runs `schedule create` again)
- Validation of the calendar itself — only the draft is validated
- Conflict detection between two drafts (only calendar-vs-draft)
- Validation on every draft edit — only on draft open

## Decisions

### Stale detection via calendar commit timestamps

On draft open, compare the draft's creation timestamp against the timestamps of calendar commits. If any calendar commit has a timestamp after the draft's creation time, the draft is stale and needs re-validation.

**Alternative considered:** Track which specific date ranges changed and only re-validate overlapping assignments. Rejected as premature optimization — the constraint checks are cheap (pure functions over small data sets), and partial validation risks missing cross-range dependencies (e.g., a change to April's calendar affects May's rest-period look-back). Full re-validation is simpler and correct.

### Build a SchedulerContext from calendar look-back for validation

To validate draft assignments, we need the same context the scheduler uses. The key integration is populating `schPrevWeekendWorkers` from the calendar. The approach:

1. Load the calendar slice for the 7 days immediately before the draft's start date (the "look-back window").
2. Identify workers who worked Saturday or Sunday in that window — these are the previous-weekend workers.
3. Build a `SchedulerContext` with the current skill, worker, absence, and config data, plus the look-back-derived `schPrevWeekendWorkers`.
4. For rest period and consecutive-hours checks, include the last day of the calendar look-back in the schedule being validated (so `violatesRestPeriod` can see the previous day's assignments when checking the draft's first day).

**Alternative considered:** Only check alternating weekends (the most likely cross-draft violation). Rejected because other constraints (rest periods, hour limits spanning week boundaries) can also be violated by calendar changes, and selective checking creates a false sense of safety.

### Validate by iterating assignments and checking canAssignSlot

For each assignment in the draft, check whether it still satisfies hard constraints by calling individual constraint predicates from `Domain/Scheduler.hs` and `Domain/Worker.hs`. We cannot use `canAssignSlot` directly because it checks against the current schedule state (which includes the assignment being tested). Instead, we check each assignment against the schedule-minus-that-assignment to simulate "would this assignment be valid if we were adding it now?"

Actually, a simpler approach: build a combined schedule (calendar look-back + draft assignments) and check each draft assignment individually using the constraint predicates. The order doesn't matter because we're checking hard constraints that are properties of individual assignments against context, not scheduling decisions that depend on other assignments.

The constraint checks to run per assignment:
- `qualified` or `couldQualifyViaCrossTraining` (skill check)
- `isWorkerAvailable` (absence check)
- `blockedByAlternateWeekend` (weekend alternation)
- `wouldBeOvertime` / `wouldExceedDailyRegular` (hour limits)
- `violatesRestPeriod` (rest between days)
- `needsBreak` (consecutive hours)
- `workerAvoidsAt` (avoid-pairing)

For each violation, record: the assignment, which constraint failed, and contextual details (e.g., "worked Apr 26-27 in calendar").

### Violation report format

Present removals grouped by worker, with specific reasons:

```
Draft "may-2026" validated against updated calendar.
3 assignments removed due to constraint violations:

  Marco (WorkerId 5):
    - May 3 grill 09:00, May 4 grill 09:00: alternating weekends
      (worked Apr 26-27 in calendar)

  Lucia (WorkerId 8):
    - May 1 grill 06:00: rest period violation
      (worked until 22:00 Apr 30 in calendar, only 8h gap)

Run 'diagnose' to see how to fill the gaps.
```

**Alternative considered:** Machine-readable JSON output. Rejected for now — the CLI is interactive and human-readable output is more useful. JSON can be added later if needed.

### New service function in Service/Draft.hs

Add `validateDraftAgainstCalendar` to the draft service module (introduced by Change 2). This function:
1. Loads the draft's creation timestamp and date range
2. Checks if any calendar commits are newer than the draft
3. If stale: loads calendar look-back, builds context, validates, removes violations, saves updated draft
4. Returns a list of `DraftViolation` records for the CLI to display

The function signature (approximate):
```haskell
validateDraftAgainstCalendar :: Repository -> DraftId -> IO [DraftViolation]
```

Where `DraftViolation` captures the assignment, the constraint name, and a human-readable reason string.

### Integration point: draft-open command handler

The CLI's draft-open handler calls `validateDraftAgainstCalendar` after loading the draft. If violations are returned, it displays the report and suggests `diagnose`. If no violations (or calendar hasn't changed), it opens the draft normally with no extra output.

## Risks / Trade-offs

**[Risk] Look-back window size assumptions** — A 7-day look-back covers alternating weekends and rest periods. If custom config has unusually long rest periods (>24h) or weekly hour calculations span more than one week, the look-back might be insufficient.
-> Mitigation: The look-back window should be at least `max(7, cfgMinRestHours / 24 + 1)` days. For the default config (8h rest, 7-day week), 7 days is sufficient. Document the assumption.

**[Risk] Draft modified after validation** — The user might have made edits to the draft that aren't captured by creation timestamp. Validation uses creation time, not last-modified time.
-> Mitigation: Use the draft's "last validated against calendar" timestamp rather than creation time. Initialize it to creation time, update it after each validation pass. This way, re-opening a draft that was already validated won't re-trigger unless the calendar changed again.

**[Risk] Performance with large drafts** — A full month of assignments for 12 workers across 5 stations could be ~1800 assignments. Each needs ~7 constraint checks.
-> Mitigation: All constraint checks are pure functions over Sets and Maps — this is O(n log n) at worst and completes in milliseconds. Not a real risk.

**[Trade-off] Auto-remove vs. warn-only** — Automatically removing assignments is opinionated. An alternative is to warn but keep the assignments, letting the user decide.
-> Decision: Auto-remove. Hard constraints are non-negotiable by definition. Keeping a violation in the draft creates a state the system considers invalid. The user can always re-assign manually.
