## 1. Database Schema

- [ ] 1.1 Add `calendar_assignments` table to `Repo/Schema.hs` with PK `(worker_id, station_id, slot_date, slot_start)`
- [ ] 1.2 Add `calendar_commits` table (id, committed_at, date_from, date_to, note)
- [ ] 1.3 Add `calendar_commit_assignments` table (commit_id, worker_id, station_id, slot_date, slot_start, slot_duration_seconds)

## 2. Repository Layer

- [ ] 2.1 Add calendar fields to `Repository` record in `Repo/Types.hs`: `repoSaveCalendar`, `repoLoadCalendar`, `repoSaveCommit`, `repoListCommits`, `repoLoadCommitAssignments`
- [ ] 2.2 Implement `sqlSaveCalendar` in `Repo/SQLite.hs` — delete existing assignments in date range, insert new ones
- [ ] 2.3 Implement `sqlLoadCalendar` in `Repo/SQLite.hs` — load assignments by date range into `Schedule`
- [ ] 2.4 Implement `sqlSaveCommit` in `Repo/SQLite.hs` — insert commit metadata and snapshot assignments, return commit id
- [ ] 2.5 Implement `sqlListCommits` in `Repo/SQLite.hs` — list commits in reverse chronological order
- [ ] 2.6 Implement `sqlLoadCommitAssignments` in `Repo/SQLite.hs` — load snapshot for a commit id
- [ ] 2.7 Wire new SQL functions into the `Repository` record constructor

## 3. Service Layer

- [ ] 3.1 Create `Service/Calendar.hs` with `commitToCalendar` — snapshot existing then overwrite
- [ ] 3.2 Add `loadCalendarSlice` — thin wrapper over repo load
- [ ] 3.3 Add `listCalendarHistory` and `viewCommit` — thin wrappers over repo history queries

## 4. CLI Commands

- [ ] 4.1 Add `CalendarCommand` variants to `CLI/Commands.hs` parser: view, view-by-worker, view-by-station, view-compact, hours, diagnose, commit, history
- [ ] 4.2 Add `calendar` to help command group list in `CLI/App.hs`
- [ ] 4.3 Implement `calendar view` handler — load slice, pass to existing `displaySchedule`
- [ ] 4.4 Implement `calendar view-by-worker` handler — load slice, pass to existing display
- [ ] 4.5 Implement `calendar view-by-station` handler — load slice, pass to existing display
- [ ] 4.6 Implement `calendar view-compact` handler — load slice, pass to existing compact display
- [ ] 4.7 Implement `calendar hours` handler — load slice, pass to existing hours display
- [ ] 4.8 Implement `calendar diagnose` handler — load slice, pass to existing diagnosis
- [ ] 4.9 Implement `calendar commit` handler — load named schedule, call `commitToCalendar`
- [ ] 4.10 Implement `calendar history` handler — list commits, format output
- [ ] 4.11 Implement `calendar history <id>` handler — load snapshot, display

## 5. Testing

- [ ] 5.1 Add tests for calendar save/load round-trip (empty range, populated range, overwrite)
- [ ] 5.2 Add tests for history snapshot correctness (commit creates snapshot, snapshot matches pre-overwrite state)
- [ ] 5.3 Add tests for date range semantics (partial overlap overwrites correctly, sparse assignments clear full range)
- [ ] 5.4 Add tests for `commitToCalendar` service (snapshot-then-overwrite atomicity)
