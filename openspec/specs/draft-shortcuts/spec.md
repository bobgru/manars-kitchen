## ADDED Requirements

### Requirement: Draft this-month shortcut
The system SHALL provide a `draft this-month` command that creates a draft for the remainder of the current month. The date range SHALL be from tomorrow (today + 1) through the last day of the current month.

#### Scenario: Create this-month draft mid-month
- **WHEN** today is Apr 8 and user types `draft this-month`
- **THEN** a draft is created for Apr 9 through Apr 30

#### Scenario: Create this-month draft on first of month
- **WHEN** today is Apr 1 and user types `draft this-month`
- **THEN** a draft is created for Apr 2 through Apr 30

#### Scenario: This-month on last day of month
- **WHEN** today is Apr 30 and user types `draft this-month`
- **THEN** system displays an error: no remaining days in the current month

#### Scenario: This-month respects non-overlapping constraint
- **WHEN** a draft already exists covering Apr 15-30 and today is Apr 8
- **THEN** `draft this-month` (which would create Apr 9-30) fails due to overlap with the existing draft

### Requirement: Draft next-month shortcut
The system SHALL provide a `draft next-month` command that creates a draft for the entire next calendar month.

#### Scenario: Create next-month draft
- **WHEN** today is Apr 8 and user types `draft next-month`
- **THEN** a draft is created for May 1 through May 31

#### Scenario: Next-month in December
- **WHEN** today is Dec 15 and user types `draft next-month`
- **THEN** a draft is created for Jan 1 through Jan 31 of the following year

#### Scenario: Next-month respects non-overlapping constraint
- **WHEN** a draft already exists covering May 1-31 and user types `draft next-month` in April
- **THEN** creation fails due to overlap with the existing draft

### Requirement: Shortcuts create standard drafts
The drafts created by `this-month` and `next-month` SHALL be identical in behavior to drafts created by `draft create <start> <end>`. They follow the same seeding logic, support the same commands (generate, view, commit, discard), and enforce the same non-overlapping constraint.

#### Scenario: This-month draft supports generate
- **WHEN** a draft was created via `draft this-month`
- **THEN** `draft generate` works identically to a manually created draft

#### Scenario: Concurrent this-month and next-month
- **WHEN** user creates a draft via `draft this-month` (Apr 9-30) and then `draft next-month` (May 1-31)
- **THEN** both drafts are active simultaneously since their ranges do not overlap
