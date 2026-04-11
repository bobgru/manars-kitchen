## 1. Database Schema

- [x] 1.1 Add `drafts` table to `Repo/Schema.hs` with columns: `draft_id` (INTEGER PRIMARY KEY AUTOINCREMENT), `date_from` (TEXT, ISO date), `date_to` (TEXT, ISO date), `created_at` (TEXT, ISO timestamp)
- [x] 1.2 Add `draft_assignments` table to `Repo/Schema.hs` with columns: `draft_id` (INTEGER FK to drafts), `worker_id`, `station_id`, `slot_date`, `slot_start`, `slot_duration_seconds` -- same shape as `calendar_assignments` plus draft_id, PK `(draft_id, worker_id, station_id, slot_date, slot_start)`

## 2. Repository Layer

- [x] 2.1 Add draft fields to `Repository` record in `Repo/Types.hs`: `repoCreateDraft`, `repoDeleteDraft`, `repoListDrafts`, `repoGetDraft`, `repoCheckDraftOverlap`, `repoSaveDraftAssignments`, `repoLoadDraftAssignments`
- [x] 2.2 Implement `sqlCreateDraft` in `Repo/SQLite.hs` -- insert row into `drafts`, return draft_id
- [x] 2.3 Implement `sqlDeleteDraft` in `Repo/SQLite.hs` -- delete from `draft_assignments` where draft_id=?, then delete from `drafts` where draft_id=?
- [x] 2.4 Implement `sqlListDrafts` in `Repo/SQLite.hs` -- select all from `drafts` ordered by created_at
- [x] 2.5 Implement `sqlGetDraft` in `Repo/SQLite.hs` -- select from `drafts` where draft_id=?
- [x] 2.6 Implement `sqlCheckDraftOverlap` in `Repo/SQLite.hs` -- select exists from `drafts` where date_from <= ? AND date_to >= ? (using new draft's to and from)
- [x] 2.7 Implement `sqlSaveDraftAssignments` in `Repo/SQLite.hs` -- delete existing for draft_id, insert new assignments
- [x] 2.8 Implement `sqlLoadDraftAssignments` in `Repo/SQLite.hs` -- select assignments for draft_id, return as `Schedule`
- [x] 2.9 Wire new SQL functions into the `Repository` record constructor

## 3. Service Layer

- [x] 3.1 Create `Service/Draft.hs` with `createDraft` -- check overlap, generate slot list, seed from calendar + pins, save draft assignments, return draft_id
- [x] 3.2 Add `seedDraft` helper -- load calendar slice, expand pins, merge with pin precedence (conflict key: worker_id + slot_date + slot_start)
- [x] 3.3 Add `generateDraft` -- load draft assignments as seed, build slot list for draft range, call `buildScheduleFrom`, save result back to draft
- [x] 3.4 Add `commitDraft` -- load draft assignments, call `commitToCalendar` from Service/Calendar.hs, delete draft
- [x] 3.5 Add `discardDraft` -- delete draft (delegates to repo)
- [x] 3.6 Add `listDrafts` and `loadDraft` -- thin wrappers over repo

## 4. CLI Commands

- [x] 4.1 Add `DraftCommand` variants to `CLI/Commands.hs` parser: create, this-month, next-month, list, open, view, view-compact, generate, commit, discard, hours, diagnose
- [x] 4.2 Add `draft` to help command group list in `CLI/App.hs`
- [x] 4.3 Implement `draft create` handler -- parse dates, call `createDraft`, display draft_id
- [x] 4.4 Implement `draft this-month` handler -- compute date range (today+1 through end of month), call `createDraft`
- [x] 4.5 Implement `draft next-month` handler -- compute date range (first through last of next month), call `createDraft`
- [x] 4.6 Implement `draft list` handler -- call `listDrafts`, format output
- [x] 4.7 Implement `draft open` handler -- call `loadDraft`, display metadata and assignment count
- [x] 4.8 Implement `draft view` handler -- load draft assignments, pass to existing display functions
- [x] 4.9 Implement `draft view-compact` handler -- load draft assignments, pass to compact display
- [x] 4.10 Implement `draft generate` handler -- call `generateDraft`, display result
- [x] 4.11 Implement `draft commit` handler -- call `commitDraft`, display confirmation
- [x] 4.12 Implement `draft discard` handler -- call `discardDraft`, display confirmation
- [x] 4.13 Implement `draft hours` handler -- load draft assignments, pass to hours display
- [x] 4.14 Implement `draft diagnose` handler -- load draft assignments, pass to diagnose display
- [x] 4.15 Implement optional draft-id resolution -- when no id given and exactly one draft exists, use it; when 0 or 2+, error with list

## 5. Seeding Logic

- [x] 5.1 Implement slot list generation for a date range using shift definitions (reuse/extract from existing `schedule create` flow)
- [x] 5.2 Implement pin-calendar merge with pin precedence -- build map keyed by (worker_id, slot_date, slot_start), pins overwrite calendar entries
- [x] 5.3 Unit test: seeding with empty calendar returns only pin expansions
- [x] 5.4 Unit test: seeding with no pins returns only calendar assignments
- [x] 5.5 Unit test: seeding with conflicting pin and calendar assignments returns pin version
- [x] 5.6 Unit test: seeding with non-conflicting assignments returns union

## 6. Integration Testing

- [x] 6.1 Test draft create/list/delete round-trip
- [x] 6.2 Test non-overlapping constraint rejection
- [x] 6.3 Test draft generate produces a valid schedule within the draft
- [x] 6.4 Test draft commit writes to calendar and creates history entry
- [x] 6.5 Test draft discard leaves calendar unchanged
- [x] 6.6 Test concurrent drafts (this-month + next-month) can coexist
- [x] 6.7 Test this-month and next-month date range computation
