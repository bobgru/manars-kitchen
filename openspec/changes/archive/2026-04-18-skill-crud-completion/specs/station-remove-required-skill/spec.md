## ADDED Requirements

### Requirement: Remove required skill from station via CLI

The system SHALL provide a `station remove-required-skill <station-id> <skill-id>` command that removes a single skill from a station's required skills set.

#### Scenario: Remove existing required skill

- **WHEN** user runs `station remove-required-skill <station> <skill>` for a station that requires the specified skill
- **THEN** the skill is removed from the station's required skills and a confirmation message is printed

#### Scenario: Remove skill not required by station

- **WHEN** user runs `station remove-required-skill <station> <skill>` for a station that does not require the specified skill
- **THEN** the command completes as a no-op (the set is unchanged)

### Requirement: station remove-required-skill requires admin

The `station remove-required-skill` command SHALL require admin privileges.

#### Scenario: Non-admin attempts removal

- **WHEN** a non-admin user runs `station remove-required-skill <station> <skill>`
- **THEN** the command is rejected with a permission error
