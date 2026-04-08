## ADDED Requirements

### Requirement: Help command shows group summary by default
The system SHALL display a list of command groups with one-line descriptions when the user types `help` with no arguments. Each group name SHALL be displayed with its description. The output SHALL NOT include individual command details.

#### Scenario: User types help with no arguments
- **WHEN** user types `help`
- **THEN** system displays a list of command groups (e.g., schedule, worker, skill, station, shift, absence, config, pin, export, audit) each with a short description, and a hint: "Type 'help <group>' for details."

### Requirement: Help command filters by group
The system SHALL display only commands belonging to the specified group when the user types `help <group>`. The group name SHALL be matched case-insensitively. Commands SHALL be shown with usage syntax and a brief description, matching the level of detail in the current help output.

#### Scenario: User types help with a valid group name
- **WHEN** user types `help schedule`
- **THEN** system displays only schedule-related commands with their syntax and descriptions

#### Scenario: User types help with an invalid group name
- **WHEN** user types `help foobar`
- **THEN** system displays an error message listing available group names

### Requirement: Command groups cover all commands
Every command in the system SHALL belong to exactly one help group. The set of groups SHALL include at minimum: schedule, worker, skill, station, shift, absence, config, pin, export, audit, and general (for help, quit, password).

#### Scenario: All commands accounted for
- **WHEN** a new command is added to the system
- **THEN** the command MUST be assigned to a help group to appear in `help <group>` output

### Requirement: Admin-only commands marked in group help
When displaying group help, commands that require admin privileges SHALL be visually distinguished from commands available to all users. Non-admin users SHALL only see commands they can use, consistent with the current role-based filtering.

#### Scenario: Non-admin user requests group help
- **WHEN** a non-admin user types `help worker`
- **THEN** system displays only the worker commands available to non-admin users

#### Scenario: Admin user requests group help
- **WHEN** an admin user types `help worker`
- **THEN** system displays all worker commands including admin-only ones
