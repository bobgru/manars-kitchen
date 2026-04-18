## ADDED Requirements

### Requirement: View individual skill details via CLI

The system SHALL provide a `skill view <id>` command that displays all information about a single skill: name, description, direct implications (what it implies and what implies it), transitive effective skills, workers who hold it, stations that require it, and workers cross-training toward it.

#### Scenario: View skill with full context

- **WHEN** user runs `skill view <id>` for a skill that has a description, implications, workers, stations, and cross-training references
- **THEN** the output shows the skill name, description, direct implications in both directions, effective (transitive) skills, worker list, station list, and cross-training worker list

#### Scenario: View skill with no references

- **WHEN** user runs `skill view <id>` for a skill with no implications, workers, stations, or cross-training
- **THEN** the output shows the skill name and description, with each reference section showing "(none)" or equivalent

#### Scenario: View nonexistent skill

- **WHEN** user runs `skill view <id>` for an ID that does not exist
- **THEN** the command prints an error indicating the skill was not found
