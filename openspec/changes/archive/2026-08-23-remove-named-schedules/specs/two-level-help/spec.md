## MODIFIED Requirements

### Requirement: Help command shows group summary by default
The system SHALL display a list of command groups with one-line descriptions when the user types `help` with no arguments. Each group name SHALL be displayed with its description. The output SHALL NOT include individual command details.

#### Scenario: User types help with no arguments
- **WHEN** user types `help`
- **THEN** system displays a list of command groups (e.g., draft, calendar, worker, skill, station, shift, absence, config, pin, export, audit) each with a short description, and a hint: "Type 'help <group>' for details."

### Requirement: Help command filters by group
The system SHALL display only commands belonging to the specified group when the user types `help <group>`. The group name SHALL be matched case-insensitively. Commands SHALL be shown with usage syntax and a brief description, matching the level of detail in the current help output.

#### Scenario: User types help with a valid group name
- **WHEN** user types `help draft`
- **THEN** system displays only draft-related commands with their syntax and descriptions

#### Scenario: User types help with an invalid group name
- **WHEN** user types `help foobar`
- **THEN** system displays an error message listing available group names

#### Scenario: The schedule group no longer exists
- **WHEN** user types `help schedule`
- **THEN** system displays the invalid-group error listing available group names

### Requirement: Command groups cover all commands
Every command in the system SHALL belong to exactly one help group. The set of groups SHALL include at minimum: draft, calendar, worker, skill, station, shift, absence, config, pin, what-if, export, audit, and general (for help, quit, password).

#### Scenario: All commands accounted for
- **WHEN** a new command is added to the system
- **THEN** the command MUST be assigned to a help group to appear in `help <group>` output

#### Scenario: What-if group exists
- **WHEN** user types `help`
- **THEN** output includes `what-if` in the command group list with description "What-if hint exploration within drafts"
