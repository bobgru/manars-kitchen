## ADDED Requirements

### Requirement: API client module for stations

The system SHALL provide `web/src/api/stations.ts` with functions:
- `fetchStations(): Promise<Station[]>` — GET /api/stations
- `createStation(name: string): Promise<void>` — POST /api/stations
- `deleteStation(name: string): Promise<DeleteResult>` — DELETE /api/stations/:name
- `forceDeleteStation(name: string): Promise<void>` — DELETE /api/stations/:name/force
- `renameStation(name: string, newName: string): Promise<void>` — PUT /api/stations/:name

All functions SHALL use the existing `apiFetch` wrapper.

#### Scenario: API client uses name-based endpoints

- **WHEN** `deleteStation("Grill")` is called
- **THEN** it SHALL send `DELETE /api/stations/Grill`

### Requirement: Stations list page

Route `/stations` SHALL display a table of all stations with columns: Name, Min Staff, Max Staff. Station names SHALL link to the detail page at `/stations/:name`.

#### Scenario: Stations table display

- **WHEN** user navigates to `/stations`
- **THEN** a table is shown with all stations, their names linking to detail pages, and staffing columns

#### Scenario: Empty state

- **WHEN** no stations exist
- **THEN** the page SHALL display "No stations defined"

### Requirement: Create station from list page

The stations list page SHALL include a create form with a name text input. Submitting the form SHALL call `POST /api/stations` and refresh the list.

#### Scenario: Create station successfully

- **WHEN** user enters "Grill" and submits
- **THEN** the station is created and the list refreshes to show it

#### Scenario: Create station with duplicate name

- **WHEN** user submits a name that already exists
- **THEN** the UI SHALL display the error message from the 409 response

### Requirement: Delete station from list page

Each station row SHALL have a delete button.

#### Scenario: Delete unreferenced station

- **WHEN** user clicks delete on a station with no references
- **THEN** the station is deleted and the list refreshes

#### Scenario: Delete referenced station shows confirmation

- **WHEN** user clicks delete on a station with references
- **THEN** a modal SHALL display the references with "Cancel" and "Force Delete" options

#### Scenario: User confirms force delete

- **WHEN** user clicks "Force Delete" in the modal
- **THEN** the station and all references are removed and the list refreshes

### Requirement: Station detail page

Route `/stations/:name` SHALL display the station's name, min staff, and max staff.

#### Scenario: View station details

- **WHEN** user navigates to `/stations/Grill`
- **THEN** the page shows station name "Grill", min staff, and max staff values

#### Scenario: Station not found

- **WHEN** user navigates to `/stations/Nonexistent`
- **THEN** the page SHALL display "Station not found" with a link back to the list

### Requirement: Rename station from detail page

The detail page SHALL include an editable name field with a save button. Saving SHALL call `PUT /api/stations/:name` and navigate to the new URL if the name changed.

#### Scenario: Rename station

- **WHEN** user changes the name from "Grill" to "Main Grill" and clicks save
- **THEN** the station is renamed and the URL updates to `/stations/Main%20Grill`

### Requirement: Sidebar link for stations

The sidebar SHALL include a "Stations" link that navigates to `/stations`.

#### Scenario: Navigate via sidebar

- **WHEN** user clicks "Stations" in the sidebar
- **THEN** the browser navigates to `/stations` and the stations list page is displayed

### Requirement: Loading and error states

The stations pages SHALL show a loading indicator while fetching data and an error message if a fetch or mutation fails.

#### Scenario: Loading state

- **WHEN** stations are being fetched
- **THEN** a loading indicator is shown

#### Scenario: Network error

- **WHEN** a fetch fails
- **THEN** an error message is displayed
