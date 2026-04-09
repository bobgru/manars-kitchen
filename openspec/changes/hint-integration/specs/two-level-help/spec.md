## MODIFIED Requirements

### Requirement: Command groups cover all commands
Every command in the system SHALL belong to exactly one help group. The set of groups SHALL include at minimum: schedule, worker, skill, station, shift, absence, config, pin, what-if, export, audit, and general (for help, quit, password).

#### Scenario: All commands accounted for
- **WHEN** a new command is added to the system
- **THEN** the command MUST be assigned to a help group to appear in `help <group>` output

#### Scenario: What-if group exists
- **WHEN** user types `help`
- **THEN** output includes `what-if` in the command group list with description "What-if hint exploration within drafts"

#### Scenario: What-if group details
- **WHEN** user types `help what-if`
- **THEN** system displays all what-if subcommands: close-station, pin, add-worker, waive-overtime, grant-skill, override-prefs, revert, revert-all, list, apply -- each with syntax and description
