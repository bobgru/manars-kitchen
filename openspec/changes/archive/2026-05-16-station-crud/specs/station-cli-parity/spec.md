## ADDED Requirements

### Requirement: Station create command

The system SHALL provide `station create <name>` to create a station. This replaces the former `station add` command.

#### Scenario: Create a station

- **WHEN** admin runs `station create "Grill"`
- **THEN** a station named "Grill" is created with default staffing and a confirmation message is printed

### Requirement: Station delete command with safe check

The system SHALL provide `station delete <name>` that checks for references before deleting. If the station is referenced by worker preferences, required skills, or assignments, the delete SHALL fail with an error listing the references.

#### Scenario: Delete unreferenced station

- **WHEN** admin runs `station delete "Grill"` and no references exist
- **THEN** the station is deleted and a confirmation message is printed

#### Scenario: Delete referenced station

- **WHEN** admin runs `station delete "Grill"` and workers have it in their station preferences
- **THEN** the system SHALL print an error listing the references and not delete the station

### Requirement: Station force-delete command

The system SHALL provide `station force-delete <name>` that removes all references to the station and then deletes it.

#### Scenario: Force delete referenced station

- **WHEN** admin runs `station force-delete "Grill"` and workers have it in their preferences
- **THEN** the station is removed from all preferences, required skills, and assignments, and then deleted

### Requirement: Station rename command

The system SHALL provide `station rename <name> <new-name>` to rename a station.

#### Scenario: Rename station

- **WHEN** admin runs `station rename "Grill" "Main Grill"`
- **THEN** the station's name SHALL be updated to "Main Grill" and a confirmation message is printed

### Requirement: Station view command

The system SHALL provide `station view <name>` that displays the station's name, min/max staffing, and required skills.

#### Scenario: View station details

- **WHEN** admin runs `station view "Grill"`
- **THEN** the system SHALL display the station name, min staff, max staff, and list of required skills

### Requirement: Station list command

The system SHALL provide `station list` that displays all station names.

#### Scenario: List stations

- **WHEN** user runs `station list`
- **THEN** the system SHALL display all station names

#### Scenario: List stations when none exist

- **WHEN** user runs `station list` and no stations exist
- **THEN** the system SHALL display "(no stations)"

### Requirement: All station commands accept names

All station commands that reference a station SHALL accept the station name as the argument, not a numeric ID. Name resolution SHALL be case-insensitive.

#### Scenario: Station set-hours by name

- **WHEN** admin runs `station set-hours "Grill" 8 16`
- **THEN** the system resolves "Grill" to the station and sets its hours

#### Scenario: Station require-skill by names

- **WHEN** admin runs `station require-skill "Grill" "Cooking"`
- **THEN** the system resolves both names and adds the skill requirement

### Requirement: Station commands require admin

All station mutation commands (create, delete, force-delete, rename, set-hours, close-day, require-skill, remove-required-skill) SHALL require admin privileges. List and view SHALL not require admin.

#### Scenario: Non-admin attempts station create

- **WHEN** a non-admin user runs `station create "Grill"`
- **THEN** the command SHALL be rejected with a permission error
