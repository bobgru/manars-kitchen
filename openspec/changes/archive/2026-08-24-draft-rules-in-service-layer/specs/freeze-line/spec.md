## ADDED Requirements

### Requirement: Refusal on draft creation touching frozen dates
When a draft is created with a date range that includes dates on or before the
freeze line, and those dates have not been explicitly unfrozen, the system SHALL
refuse to create the draft and SHALL report the freeze line and the frozen
sub-range of the requested range.

The check SHALL live in `Service.Draft.createDraft`, which receives the caller's
force flag and its set of active unfrozen ranges as `CreateDraftOpts`. The refusal
SHALL be structured — naming the freeze line, the first frozen date and the last
frozen date — so that each client can render it in its own idiom. There SHALL be
no interactive confirmation: the CLI names the two ways forward (`calendar
unfreeze` or `--force`) and returns to the prompt.

A caller that supplies no unfrozen ranges and no force flag — which is every REST
caller, since neither is exposed over HTTP — SHALL therefore be refused for any
range containing a frozen date.

#### Scenario: Draft entirely in the future
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-08 to 2026-04-14
- **THEN** no freeze refusal occurs and the draft is created normally

#### Scenario: Draft entirely in the past
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-01 to 2026-04-05
- **THEN** the draft is NOT created
- **AND** the refusal names the freeze line 2026-04-07 and the frozen range 2026-04-01 to 2026-04-05

#### Scenario: Draft spanning the freeze line
- **WHEN** the freeze line is 2026-04-07 and a draft is created for 2026-04-05 to 2026-04-12
- **THEN** the refusal identifies 2026-04-05 through 2026-04-07 as the frozen range
- **AND** the unfrozen remainder of the range is not mentioned

#### Scenario: CLI names both ways forward
- **WHEN** the CLI refuses `draft create 2026-04-05 2026-04-12`
- **THEN** it prints the frozen range, a `calendar unfreeze` command for that range, and the same `draft create` with `--force`

#### Scenario: Force overrides the refusal
- **WHEN** the user types `draft create 2026-04-01 2026-04-05 --force`
- **THEN** the draft is created despite the frozen dates

#### Scenario: Draft touching unfrozen dates passes without refusal
- **WHEN** the freeze line is 2026-04-07 and dates 2026-04-01 to 2026-04-07 have been explicitly unfrozen
- **AND** a draft is created for 2026-04-01 to 2026-04-14
- **THEN** no refusal occurs and the draft is created normally

#### Scenario: Partially unfrozen range reports only what is left
- **WHEN** the freeze line is 2026-04-07, dates 2026-04-01 to 2026-04-03 have been unfrozen, and a draft is created for 2026-04-01 to 2026-04-14
- **THEN** the refusal names the frozen range 2026-04-04 to 2026-04-07

#### Scenario: REST creation over frozen dates returns 409
- **WHEN** `POST /api/drafts` requests a range whose dates are on or before the freeze line
- **THEN** the response is 409 Conflict
- **AND** the body carries an `error` message plus the `freezeLine`, `frozenFrom` and `frozenTo` dates
- **AND** no draft is created

## MODIFIED Requirements

### Requirement: Auto-refreeze on draft commit
After a draft is committed that included dates on or before the freeze line, the
system SHALL clear ALL temporary unfreezes from the session and display a message
confirming the refreeze.

The decision that a committed range included historical dates SHALL be made by
`Service.Draft.commitDraft` and reported to the caller as part of its outcome. The
caller clears its own session state; a caller holding no unfreezes takes no action
and displays nothing.

#### Scenario: Commit draft with unfrozen historical dates
- **WHEN** dates 2026-04-01 to 2026-04-05 were unfrozen and a draft covering those dates is committed
- **THEN** the commit outcome reports that the range covered frozen dates
- **AND** all temporary unfreezes are cleared
- **AND** the system displays "Historical dates refrozen. All temporary unfreezes cleared."

#### Scenario: Commit draft with only future dates
- **WHEN** a draft covering only future dates is committed and no unfreezes are active
- **THEN** the commit outcome reports that the range covered no frozen dates
- **AND** no refreeze message is displayed

#### Scenario: Commit clears unrelated unfreezes too
- **WHEN** dates 2026-04-01 to 2026-04-03 and 2026-03-20 to 2026-03-25 were unfrozen
- **AND** a draft covering only 2026-04-01 to 2026-04-10 is committed
- **THEN** ALL unfreezes are cleared (including the 2026-03-20 to 2026-03-25 range)

#### Scenario: Commit over REST cannot clear a CLI session's unfreezes
- **WHEN** an admin unfreezes dates in a CLI session and then commits the draft via `POST /api/drafts/:id/commit`
- **THEN** the commit succeeds and reports that the range covered frozen dates
- **AND** the CLI session's unfreezes remain, because unfrozen ranges are session state that the server process never held

## REMOVED Requirements

### Requirement: Warning on draft creation touching frozen dates
**Reason**: Renamed, because the behaviour is a refusal rather than a warning.
This requirement described an interactive `Proceed anyway? (y/N)` confirmation
that was never implemented — the CLI has always refused outright and named
`calendar unfreeze` and `--force` as the two ways forward. Replaced by
`Refusal on draft creation touching frozen dates` above, which also records
where the check lives and what a REST caller sees.
