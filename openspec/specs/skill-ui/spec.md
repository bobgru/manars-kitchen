## ADDED Requirements

### Requirement: Create skill from UI

The skills list page SHALL include a "New Skill" button that allows the user to create a new skill by providing an ID and name.

#### Scenario: Create skill successfully

- **WHEN** user clicks "New Skill", enters an ID and name, and submits
- **THEN** the skill is created via `POST /api/skills` and the skills list refreshes to show the new skill

#### Scenario: Create skill with duplicate ID

- **WHEN** user submits a new skill with an ID that already exists
- **THEN** the UI displays the error message from the 409 response

### Requirement: Delete skill from UI

Each skill row in the skills list page SHALL have a "Delete" button.

#### Scenario: Delete unreferenced skill

- **WHEN** user clicks "Delete" on a skill with no references
- **THEN** the skill is deleted via `DELETE /api/skills/:id` and the list refreshes

#### Scenario: Delete referenced skill shows confirmation

- **WHEN** user clicks "Delete" on a skill with references
- **THEN** the UI receives a 409 response and displays a confirmation dialog showing the references (workers, stations, implications, cross-training) with "Cancel" and "Force Delete" options

#### Scenario: User confirms force delete

- **WHEN** user clicks "Force Delete" in the confirmation dialog
- **THEN** the UI calls `DELETE /api/skills/:id/force`, the skill and all references are removed, and the list refreshes

#### Scenario: User cancels force delete

- **WHEN** user clicks "Cancel" in the confirmation dialog
- **THEN** the dialog closes and no changes are made
