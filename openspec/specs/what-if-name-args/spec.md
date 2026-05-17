# What-If Name Args

`what-if` commands that reference workers take worker names; existing skill/station name resolution preserved.

## Requirements

### Requirement: what-if commands take worker name where applicable
The system SHALL accept worker names for `what-if` commands that reference a worker:
`what-if pin <name> <station-name> <date> <hour>`,
`what-if grant-skill <name> <skill-name>`,
`what-if waive-overtime <name>`,
`what-if override-prefs <name> <station-name...>`.
The `what-if add-worker <name> <skills...>` command (which creates a *temporary* worker with a fresh display name) is unchanged in shape — its `<name>` argument is still a free-form display name for the temporary worker, and skill arguments are skill names. Numeric ids SHALL still be accepted for resolution-aware verbs.

#### Scenario: what-if pin by names
- **WHEN** an admin runs `what-if pin alice grill 2026-04-06 9`
- **THEN** the system resolves `alice` and `grill` to ids and adds a pin hint, then displays the diff

#### Scenario: what-if grant-skill by names
- **WHEN** an admin runs `what-if grant-skill alice grill`
- **THEN** the system resolves names and adds a `GrantSkill` hint, then displays the diff

#### Scenario: what-if waive-overtime by name
- **WHEN** an admin runs `what-if waive-overtime alice`
- **THEN** the system resolves `alice` to her `WorkerId` and adds a `WaiveOvertime` hint

#### Scenario: what-if override-prefs by names
- **WHEN** an admin runs `what-if override-prefs alice grill prep`
- **THEN** the system resolves `alice`, `grill`, `prep` to ids and adds an `OverridePreference` hint

#### Scenario: what-if add-worker still uses free-form name
- **WHEN** an admin runs `what-if add-worker temp1 grill 20`
- **THEN** the system creates a temporary worker hint with display name `temp1`, skill `grill`, and 20-hour limit; no resolution against existing users
