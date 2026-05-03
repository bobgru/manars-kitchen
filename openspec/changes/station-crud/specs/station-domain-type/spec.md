## ADDED Requirements

### Requirement: Station domain type

The system SHALL define a `Station` record type with fields `stationName :: Text`, `stationMinStaff :: Int`, and `stationMaxStaff :: Int`.

#### Scenario: Station type replaces bare tuple

- **WHEN** the repository lists stations
- **THEN** it SHALL return `[(StationId, Station)]` instead of `[(StationId, Text)]`

### Requirement: Repository returns Station records

`repoListStations` SHALL return `IO [(StationId, Station)]` where each `Station` includes the name, min_staff, and max_staff from the database row.

#### Scenario: List stations includes staffing data

- **WHEN** a station exists with name "Grill", min_staff 1, max_staff 2
- **THEN** `repoListStations` SHALL return a list containing `(stationId, Station "Grill" 1 2)`

### Requirement: Repository supports station rename

The system SHALL provide `repoRenameStation :: StationId -> Text -> IO ()` that updates the station's name in the database.

#### Scenario: Rename station in database

- **WHEN** `repoRenameStation sid "New Name"` is called
- **THEN** the station's name in the `stations` table SHALL be updated to "New Name"
