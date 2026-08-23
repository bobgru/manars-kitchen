## MODIFIED Requirements

### Requirement: Generate schedule within a draft
The system SHALL support running the scheduler within a draft. The scheduler SHALL receive the
draft's current assignments as the seed schedule and the draft's date range slots. The result
SHALL replace the draft's assignments.

Generation SHALL go through the optimizer rather than a single greedy pass. When
`opt-enabled` is `0` the optimizer runs the greedy build once and returns, so generation is
unchanged; when `opt-enabled` is greater than `0` the optimizer's hard-constraint and
soft-constraint phases run under the configured time limit. Generation SHALL accept a progress
bus and publish `OptimizeProgress` events to it.

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

#### Scenario: Optimization disabled leaves generation unchanged
- **WHEN** `opt-enabled` is `0` and `draft generate` is run
- **THEN** the result is the single greedy build of the seed against the draft's context
- **AND** no progress event is published

#### Scenario: Optimization enabled over a weekday range
- **WHEN** `opt-enabled` is greater than `0`, `opt-time-limit-secs` is set, and `draft generate`
  is run over a range containing no Saturday
- **THEN** generation returns within roughly that limit with the best result found

#### Scenario: Optimization enabled over a range containing a weekend
- **WHEN** `opt-enabled` is greater than `0` and `draft generate` is run over a range containing
  a Saturday
- **THEN** generation SHALL return within roughly `opt-time-limit-secs`
- **NOTE** this scenario currently fails: the iterated-greedy rebuild diverges on the
  weekend-constraint path and allocates without bound, and the time limit is only checked
  between iterations so it cannot interrupt it. The behaviour pre-dates this change and is
  unreachable at the default `opt-enabled` of `0`. Tracked as a pending test in
  `test/DraftSpec.hs`.
