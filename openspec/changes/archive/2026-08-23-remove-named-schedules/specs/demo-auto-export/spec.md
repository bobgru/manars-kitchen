## MODIFIED Requirements

### Requirement: Demo mode exports JSON on completion
The system SHALL automatically export the full system state as JSON after the demo command replay completes. The export file SHALL be written to a well-known location and the path SHALL be printed to the user.

#### Scenario: Demo completes and exports
- **WHEN** demo mode finishes replaying all commands
- **THEN** system exports full JSON to a file (e.g., `demo-export.json` or alongside the demo database) and prints: "Exported demo data to <path>"

#### Scenario: Demo export includes all entities
- **WHEN** demo export is written
- **THEN** the JSON file contains all skills, stations, workers, absence types and skill implications created during the demo
- **AND** it carries no `schedules` key, named schedules having been removed
