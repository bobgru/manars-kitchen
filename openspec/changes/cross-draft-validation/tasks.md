## 1. Domain Types and Validation Logic

- [ ] 1.1 Define `DraftViolation` type capturing: the removed assignment, constraint name (e.g., "alternating weekends"), and a human-readable reason string with context details
- [ ] 1.2 Implement `validateAssignment` function that checks a single assignment against all hard constraints (skill, absence, alternating weekends, weekly hours, daily hours, rest period, consecutive hours, avoid-pairing) and returns the first violated constraint or Nothing
- [ ] 1.3 Implement `buildLookBackContext` function that takes a calendar look-back schedule (7 days before draft start) and extracts `schPrevWeekendWorkers` and a combined schedule for rest-period/consecutive-hours boundary checks

## 2. Service Layer

- [ ] 2.1 Add `validateDraftAgainstCalendar :: Repository -> DraftId -> IO [DraftViolation]` to `Service/Draft.hs` — orchestrates stale detection, context loading, validation, removal, and timestamp update
- [ ] 2.2 Implement stale detection: query calendar commits with timestamps after the draft's last-validated timestamp; short-circuit with empty list if not stale
- [ ] 2.3 Implement look-back loading: load calendar slice for 7 days before draft start date, build `SchedulerContext` with current skill/worker/absence/config data plus look-back-derived previous-weekend workers
- [ ] 2.4 Implement validation loop: iterate all draft assignments, check each against hard constraints, collect violations with reason strings
- [ ] 2.5 Implement auto-removal: remove violating assignments from draft, save updated draft, update last-validated timestamp

## 3. Repository Support

- [ ] 3.1 Add `repoCalendarCommitsAfter :: UTCTime -> IO [CalendarCommit]` (or equivalent) to query calendar commits newer than a given timestamp, if not already available from Change 1's repository interface
- [ ] 3.2 Add `last_validated_at` field to draft storage (if not already present from Change 2), with initial value equal to draft creation time

## 4. CLI Integration

- [ ] 4.1 Call `validateDraftAgainstCalendar` in the draft-open command handler, after loading the draft but before displaying it
- [ ] 4.2 Implement violation report display: format removals grouped by worker, with constraint name and context details, preceded by summary header with draft name and removal count
- [ ] 4.3 Display "Run 'diagnose' to see how to fill the gaps." after the violation report when removals occurred
- [ ] 4.4 Skip all validation output when no violations are found (draft opens normally)

## 5. Testing

- [ ] 5.1 Unit test: `validateAssignment` detects alternating-weekend violation when previous-weekend workers are populated from calendar look-back
- [ ] 5.2 Unit test: `validateAssignment` detects rest-period violation using calendar look-back assignments for the previous day
- [ ] 5.3 Unit test: `validateAssignment` passes when no constraints are violated
- [ ] 5.4 Integration test: `validateDraftAgainstCalendar` returns empty list when calendar has not changed since draft creation
- [ ] 5.5 Integration test: `validateDraftAgainstCalendar` removes violating assignments and returns violation list when calendar has changed
- [ ] 5.6 Integration test: second call to `validateDraftAgainstCalendar` (no further calendar changes) returns empty list due to updated last-validated timestamp
