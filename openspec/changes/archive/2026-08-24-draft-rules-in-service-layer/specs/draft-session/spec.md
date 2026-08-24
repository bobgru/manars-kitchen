## MODIFIED Requirements

### Requirement: Generate schedule within a draft
The system SHALL support running the scheduler within a draft. The scheduler SHALL receive the draft's current assignments as the seed schedule and the draft's date range slots. The result SHALL replace the draft's assignments.

Generation SHALL go through the optimizer rather than a single greedy pass. When `opt-enabled` is `0` the optimizer runs the greedy build once and returns, so generation is unchanged; when `opt-enabled` is greater than `0` the optimizer's hard-constraint and soft-constraint phases run under the configured time limit. Generation SHALL accept a progress bus and publish `OptimizeProgress` events to it.

The candidate worker set SHALL be optional. When a caller supplies no worker set,
generation SHALL use the active workers — every user whose worker status is
`active` — and SHALL NOT offer inactive workers or non-worker accounts to the
scheduler. There SHALL be exactly one definition of that default, in the service
layer, shared by the CLI and by `POST /api/drafts/:id/generate`. An explicitly
empty worker set is distinct from an absent one and SHALL schedule nobody.

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

#### Scenario: Generate with no worker set uses active workers
- **WHEN** `draft generate 1` is run with no candidate worker set
- **THEN** the scheduler's candidate set is every user whose worker status is `active`

#### Scenario: Generate with no worker set excludes a deactivated worker
- **WHEN** a worker has been deactivated and `draft generate 1` is run with no candidate worker set
- **THEN** that worker is not offered to the scheduler

#### Scenario: REST generate omits workerIds
- **WHEN** `POST /api/drafts/1/generate` is called with a body that has no `workerIds` key
- **THEN** generation runs over the active workers
- **AND** the response is the schedule result

#### Scenario: REST generate sends an empty workerIds
- **WHEN** `POST /api/drafts/1/generate` is called with `{"workerIds": []}`
- **THEN** generation runs over no workers and fills nothing

#### Scenario: Optimization disabled leaves generation unchanged
- **WHEN** `opt-enabled` is `0` and `draft generate` is run
- **THEN** the result is the single greedy build of the seed against the draft's context
- **AND** no progress event is published

#### Scenario: Optimization enabled over a weekday range
- **WHEN** `opt-enabled` is greater than `0`, `opt-time-limit-secs` is set, and `draft generate` is run over a range containing no Saturday
- **THEN** generation returns within roughly that limit with the best result found

#### Scenario: Optimization enabled over a range containing a weekend
- **WHEN** `opt-enabled` is greater than `0` and `draft generate` is run over a range containing a Saturday
- **THEN** generation SHALL return within roughly `opt-time-limit-secs`
- **NOTE** this scenario currently fails: the iterated-greedy rebuild diverges on the weekend-constraint path and allocates without bound, and the time limit is only checked between iterations so it cannot interrupt it. The behaviour pre-dates the optimizer being wired into `draft generate` and is unreachable at the default `opt-enabled` of `0`. Tracked as a pending test in `test/DraftSpec.hs`.

### Requirement: Commit a draft to the calendar
The system SHALL support committing a draft to the calendar. Committing SHALL: (1) load the draft's assignments, (2) call the calendar commit service to snapshot existing calendar assignments in the date range and overwrite with the draft's assignments, (3) delete the draft and its assignments, (4) delete every persisted what-if session for the draft.

Committing SHALL report whether the committed range included dates on or before the
freeze line, so that a caller holding temporary unfreezes can clear them. Every
rule in this list SHALL be enforced by the service layer, so that the CLI and
`POST /api/drafts/:id/commit` cannot diverge.

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

#### Scenario: Commit over REST cleans up what-if sessions
- **WHEN** a draft with a persisted what-if session is committed via `POST /api/drafts/:id/commit`
- **THEN** the what-if session row is deleted, as it is when the same draft is committed from the CLI

### Requirement: Discard a draft
The system SHALL support discarding a draft. Discarding SHALL delete the draft, all its assignments and every persisted what-if session for the draft, without modifying the calendar or history.

#### Scenario: Discard a draft
- **WHEN** a draft for Apr 1-30 is discarded
- **THEN** the draft and its assignments are deleted
- **AND** `calendar_assignments` is unchanged
- **AND** no history commit is created

#### Scenario: Discard cleans up what-if sessions
- **WHEN** a draft with a persisted what-if session is discarded
- **THEN** the what-if session row is deleted

### Requirement: Repository interface extended for drafts
The `Repository` record SHALL include new fields for draft operations: create draft, delete draft, list drafts, get draft metadata, check overlap, save/load draft assignments, and delete every what-if session belonging to a draft.

#### Scenario: Repository has draft fields
- **WHEN** a `Repository` is constructed
- **THEN** it includes `repoCreateDraft`, `repoDeleteDraft`, `repoListDrafts`, `repoGetDraft`, `repoCheckDraftOverlap`, `repoSaveDraftAssignments`, `repoLoadDraftAssignments`, `repoDeleteDraftHintSessions`
