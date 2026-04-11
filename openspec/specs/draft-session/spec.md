## ADDED Requirements

### Requirement: Draft session storage
The system SHALL maintain a `drafts` table storing draft session metadata. Each draft SHALL have a unique integer id, a date_from (Day), a date_to (Day), and a created_at timestamp. A `draft_assignments` table SHALL store assignments within a draft, with the same columns as `calendar_assignments` plus a `draft_id` foreign key.

#### Scenario: Create a draft
- **WHEN** a draft is created for date range Apr 1-30
- **THEN** a row is inserted into `drafts` with date_from=Apr 1, date_to=Apr 30, and the current timestamp
- **AND** a unique draft_id is returned

#### Scenario: Draft assignments isolated from calendar
- **WHEN** assignments are saved to a draft
- **THEN** they appear only in `draft_assignments` keyed by draft_id
- **AND** `calendar_assignments` is unchanged

### Requirement: Non-overlapping date ranges
The system SHALL reject creation of a draft whose date range overlaps with any existing draft's date range. Two ranges overlap if one's start date is on or before the other's end date and one's end date is on or after the other's start date.

#### Scenario: Create non-overlapping drafts
- **WHEN** a draft exists for Apr 1-30 and a new draft is created for May 1-31
- **THEN** the new draft is created successfully

#### Scenario: Reject overlapping draft
- **WHEN** a draft exists for Apr 1-30 and a new draft is created for Apr 15-May 15
- **THEN** creation fails with an error message identifying the conflicting draft

#### Scenario: Reject identical range
- **WHEN** a draft exists for Apr 1-30 and a new draft is created for Apr 1-30
- **THEN** creation fails with an error message identifying the conflicting draft

### Requirement: List active drafts
The system SHALL support listing all active drafts, showing draft_id, date_from, date_to, and created_at.

#### Scenario: List with multiple drafts
- **WHEN** two drafts exist (Apr 1-30 and May 1-31)
- **THEN** listing returns both drafts with their metadata

#### Scenario: List with no drafts
- **WHEN** no drafts exist
- **THEN** listing returns an empty list

### Requirement: View draft assignments
The system SHALL support loading and displaying the assignments within a draft. The assignments SHALL be returned as a `Schedule` domain type, compatible with all existing display functions.

#### Scenario: View a populated draft
- **WHEN** a draft has been seeded and contains assignments
- **THEN** viewing the draft displays assignments using the same format as `calendar view`

#### Scenario: View an empty draft
- **WHEN** a draft exists but has no assignments (e.g., date range with no calendar data and no applicable pins)
- **THEN** viewing the draft displays "No assignments in this draft."

### Requirement: Generate schedule within a draft
The system SHALL support running the scheduler within a draft. The scheduler SHALL receive the draft's current assignments as the seed schedule and the draft's date range slots. The result SHALL replace the draft's assignments.

#### Scenario: Generate fills empty slots
- **WHEN** a draft has pin-seeded assignments and empty slots remain
- **THEN** `draft generate` runs the scheduler, which fills slots according to constraints
- **AND** the draft's assignments are replaced with the scheduler's output

#### Scenario: Generate preserves pinned assignments in seed
- **WHEN** a draft's seed includes pinned assignments
- **THEN** the scheduler receives those as part of the seed and preserves them (scheduler behavior, not draft-specific)

#### Scenario: Generate can be run multiple times
- **WHEN** `draft generate` is run, then a checkpoint is created, then `draft generate` is run again
- **THEN** the second run replaces the first run's output

### Requirement: Commit a draft to the calendar
The system SHALL support committing a draft to the calendar. Committing SHALL: (1) load the draft's assignments, (2) call the calendar commit service to snapshot existing calendar assignments in the date range and overwrite with the draft's assignments, (3) delete the draft and its assignments.

#### Scenario: Commit a draft
- **WHEN** a draft for Apr 1-30 is committed with note "April final"
- **THEN** existing calendar assignments for Apr 1-30 are snapshotted to history
- **AND** the calendar is overwritten with the draft's assignments
- **AND** the draft and its assignments are deleted
- **AND** the history commit includes the note "April final"

#### Scenario: Commit empty draft
- **WHEN** a draft with no assignments is committed
- **THEN** existing calendar assignments for the date range are snapshotted and cleared
- **AND** the draft is deleted

### Requirement: Discard a draft
The system SHALL support discarding a draft. Discarding SHALL delete the draft and all its assignments without modifying the calendar or history.

#### Scenario: Discard a draft
- **WHEN** a draft for Apr 1-30 is discarded
- **THEN** the draft and its assignments are deleted
- **AND** `calendar_assignments` is unchanged
- **AND** no history commit is created

### Requirement: Draft CLI commands
The system SHALL provide a `draft` command group with subcommands: `create`, `list`, `open`, `view`, `generate`, `commit`, `discard`, `view-compact`, `hours`, `diagnose`. The `draft` group SHALL appear in the two-level help system.

#### Scenario: Draft create
- **WHEN** user types `draft create 2026-04-01 2026-04-30`
- **THEN** a draft is created for that date range and its id is displayed

#### Scenario: Draft list
- **WHEN** user types `draft list`
- **THEN** all active drafts are displayed with id, date range, and creation time

#### Scenario: Draft open
- **WHEN** user types `draft open 1`
- **THEN** draft #1's metadata and assignment summary are displayed

#### Scenario: Draft view
- **WHEN** user types `draft view 1`
- **THEN** draft #1's assignments are displayed in the standard schedule grid format

#### Scenario: Draft generate
- **WHEN** user types `draft generate 1`
- **THEN** the scheduler runs within draft #1 and the result is displayed

#### Scenario: Draft commit
- **WHEN** user types `draft commit 1 "final version"`
- **THEN** draft #1 is committed to the calendar with the given note

#### Scenario: Draft discard
- **WHEN** user types `draft discard 1`
- **THEN** draft #1 is deleted without affecting the calendar

#### Scenario: Draft view-compact
- **WHEN** user types `draft view-compact 1`
- **THEN** draft #1's assignments are displayed in compact format

#### Scenario: Draft hours
- **WHEN** user types `draft hours 1`
- **THEN** per-worker hour summaries for draft #1 are displayed

#### Scenario: Draft diagnose
- **WHEN** user types `draft diagnose 1`
- **THEN** coverage analysis for draft #1 is displayed

#### Scenario: Help shows draft group
- **WHEN** user types `help`
- **THEN** output includes `draft` in the command group list

#### Scenario: Help draft shows subcommands
- **WHEN** user types `help draft`
- **THEN** output lists all draft subcommands with brief descriptions

#### Scenario: Optional draft-id when only one draft exists
- **WHEN** exactly one draft exists and user types `draft view`
- **THEN** that draft's assignments are displayed (no id required)

#### Scenario: Ambiguous draft-id
- **WHEN** two or more drafts exist and user types `draft view` without an id
- **THEN** system displays an error listing active drafts and asking the user to specify one

### Requirement: Repository interface extended for drafts
The `Repository` record SHALL include new fields for draft operations: create draft, delete draft, list drafts, get draft metadata, check overlap, save/load draft assignments.

#### Scenario: Repository has draft fields
- **WHEN** a `Repository` is constructed
- **THEN** it includes `repoCreateDraft`, `repoDeleteDraft`, `repoListDrafts`, `repoGetDraft`, `repoCheckDraftOverlap`, `repoSaveDraftAssignments`, `repoLoadDraftAssignments`
