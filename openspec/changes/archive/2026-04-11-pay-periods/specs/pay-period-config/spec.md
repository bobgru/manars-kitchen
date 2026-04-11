## ADDED Requirements

### Requirement: Pay period configuration storage
The system SHALL store a restaurant-wide pay period configuration consisting of a period type and an anchor date. The period type SHALL be one of: `weekly`, `biweekly`, `semi-monthly`, `monthly`. The anchor date SHALL be a calendar date in YYYY-MM-DD format. At most one pay period configuration SHALL exist at any time.

#### Scenario: Save pay period config
- **WHEN** a pay period config is saved with type `biweekly` and anchor date `2026-01-05`
- **THEN** the `pay_period_config` table contains one row with period_type `biweekly` and anchor_date `2026-01-05`

#### Scenario: Overwrite existing config
- **WHEN** a pay period config already exists as `weekly` with anchor `2026-01-05`
- **AND** a new config is saved with type `monthly` and anchor `2026-01-01`
- **THEN** the table contains one row with period_type `monthly` and anchor_date `2026-01-01`

#### Scenario: No config defaults to weekly
- **WHEN** no pay period config row exists in the database
- **THEN** the system SHALL behave as if the period type is `weekly` with an anchor on the Monday of the current week

### Requirement: Pay period type validation
The system SHALL reject invalid period types. Only the values `weekly`, `biweekly`, `semi-monthly`, and `monthly` SHALL be accepted.

#### Scenario: Valid period type
- **WHEN** a config is set with period type `biweekly`
- **THEN** the config is saved successfully

#### Scenario: Invalid period type
- **WHEN** a config is set with period type `quarterly`
- **THEN** the system SHALL display an error: "Invalid period type: quarterly. Must be one of: weekly, biweekly, semi-monthly, monthly."

### Requirement: Pay period boundary computation
The system SHALL provide a function to compute the start date (inclusive) and end date (exclusive) of the pay period containing any given date.

#### Scenario: Weekly period boundaries
- **WHEN** period type is `weekly` with anchor `2026-01-05` (a Monday)
- **AND** the query date is `2026-04-08` (a Wednesday)
- **THEN** the period start is `2026-04-06` (Monday) and end is `2026-04-13` (next Monday)

#### Scenario: Biweekly period boundaries
- **WHEN** period type is `biweekly` with anchor `2026-01-05`
- **AND** the query date is `2026-04-08`
- **THEN** the period start is `2026-03-30` and end is `2026-04-13` (14-day period aligned to anchor)

#### Scenario: Semi-monthly first half
- **WHEN** period type is `semi-monthly`
- **AND** the query date is `2026-04-10`
- **THEN** the period start is `2026-04-01` and end is `2026-04-16`

#### Scenario: Semi-monthly second half
- **WHEN** period type is `semi-monthly`
- **AND** the query date is `2026-04-20`
- **THEN** the period start is `2026-04-16` and end is `2026-05-01`

#### Scenario: Monthly period boundaries
- **WHEN** period type is `monthly`
- **AND** the query date is `2026-04-15`
- **THEN** the period start is `2026-04-01` and end is `2026-05-01`

#### Scenario: Monthly period for February
- **WHEN** period type is `monthly`
- **AND** the query date is `2026-02-14`
- **THEN** the period start is `2026-02-01` and end is `2026-03-01`

### Requirement: CLI set pay period command
The system SHALL provide `config set-pay-period <type> <anchor-date>` to configure the restaurant's pay period.

#### Scenario: Set biweekly pay period
- **WHEN** user types `config set-pay-period biweekly 2026-01-05`
- **THEN** the pay period config is saved with type `biweekly` and anchor `2026-01-05`
- **AND** system displays "Pay period set to biweekly (anchor: 2026-01-05)."

#### Scenario: Set monthly pay period
- **WHEN** user types `config set-pay-period monthly 2026-01-01`
- **THEN** the pay period config is saved with type `monthly` and anchor `2026-01-01`
- **AND** system displays "Pay period set to monthly (anchor: 2026-01-01)."

#### Scenario: Set pay period with invalid type
- **WHEN** user types `config set-pay-period quarterly 2026-01-01`
- **THEN** system displays "Invalid period type: quarterly. Must be one of: weekly, biweekly, semi-monthly, monthly."

#### Scenario: Set pay period with invalid date
- **WHEN** user types `config set-pay-period biweekly not-a-date`
- **THEN** system displays "Invalid date format. Use YYYY-MM-DD."

### Requirement: CLI show pay period command
The system SHALL provide `config show-pay-period` to display the current pay period configuration and the boundaries of the current period.

#### Scenario: Show configured pay period
- **WHEN** the pay period is configured as `biweekly` with anchor `2026-01-05`
- **AND** today is `2026-04-08`
- **AND** user types `config show-pay-period`
- **THEN** system displays the period type, anchor date, and the current period's start and end dates

#### Scenario: Show default pay period
- **WHEN** no pay period config exists
- **AND** user types `config show-pay-period`
- **THEN** system displays "Pay period: weekly (default)" and the current week's boundaries

### Requirement: Repository interface for pay period config
The `Repository` record SHALL include fields for loading and saving pay period configuration: `repoLoadPayPeriodConfig` and `repoSavePayPeriodConfig`.

#### Scenario: Repository has pay period config fields
- **WHEN** a `Repository` is constructed
- **THEN** it includes `repoLoadPayPeriodConfig` and `repoSavePayPeriodConfig` fields

#### Scenario: Load when no config exists
- **WHEN** `repoLoadPayPeriodConfig` is called and no row exists in `pay_period_config`
- **THEN** it returns `Nothing`

#### Scenario: Load existing config
- **WHEN** a config has been saved with type `biweekly` and anchor `2026-01-05`
- **AND** `repoLoadPayPeriodConfig` is called
- **THEN** it returns `Just` a `PayPeriodConfig` with the saved values
