## ADDED Requirements

### Requirement: List stations returns Station objects

`GET /api/stations` SHALL return a JSON array of station objects with `name`, `minStaff`, and `maxStaff` fields. No numeric IDs SHALL be included in the response.

#### Scenario: List stations response format

- **WHEN** client sends `GET /api/stations`
- **THEN** response SHALL be `[{"name": "Grill", "minStaff": 1, "maxStaff": 2}, ...]`

### Requirement: Create station by name only

`POST /api/stations` SHALL accept `{"name": "Station Name"}` and create the station with default staffing. The request SHALL NOT include a numeric ID.

#### Scenario: Create station

- **WHEN** client sends `POST /api/stations` with `{"name": "Grill"}`
- **THEN** station is created and response is 204 No Content

#### Scenario: Create duplicate station

- **WHEN** client sends `POST /api/stations` with a name that already exists
- **THEN** response SHALL be 409 Conflict with an error message

### Requirement: Delete station by name with safe check

`DELETE /api/stations/:name` SHALL resolve the station by name and check for references. If references exist, it SHALL return 409 with a structured error listing them.

#### Scenario: Delete unreferenced station

- **WHEN** client sends `DELETE /api/stations/Grill` and no references exist
- **THEN** station is deleted and response is 204 No Content

#### Scenario: Delete referenced station

- **WHEN** client sends `DELETE /api/stations/Grill` and workers reference it
- **THEN** response SHALL be 409 Conflict with a JSON body listing the references

### Requirement: Force delete station by name

`DELETE /api/stations/:name/force` SHALL remove all references to the station and delete it unconditionally.

#### Scenario: Force delete station

- **WHEN** client sends `DELETE /api/stations/Grill/force`
- **THEN** all references are removed, station is deleted, response is 204 No Content

### Requirement: Rename station by name

`PUT /api/stations/:name` SHALL accept `{"name": "New Name"}` and rename the station.

#### Scenario: Rename station

- **WHEN** client sends `PUT /api/stations/Grill` with `{"name": "Main Grill"}`
- **THEN** station is renamed and response is 204 No Content

#### Scenario: Rename to unknown station

- **WHEN** client sends `PUT /api/stations/Nonexistent` with a new name
- **THEN** response SHALL be 404 Not Found

### Requirement: Station hours endpoint uses name

`PUT /api/stations/:name/hours` SHALL resolve the station by name instead of numeric ID.

#### Scenario: Set station hours by name

- **WHEN** client sends `PUT /api/stations/Grill/hours` with `{"start": 8, "end": 16}`
- **THEN** the system resolves "Grill" by name and sets the hours

### Requirement: Station closure endpoint uses name

`PUT /api/stations/:name/closure` SHALL resolve the station by name instead of numeric ID.

#### Scenario: Set station closure by name

- **WHEN** client sends `PUT /api/stations/Grill/closure` with `{"day": "Sunday"}`
- **THEN** the system resolves "Grill" by name and sets the closure

### Requirement: All station endpoints require authentication

All station mutation endpoints SHALL require admin authentication. The list endpoint SHALL require any authenticated role.

#### Scenario: Unauthenticated request

- **WHEN** client sends `POST /api/stations` without authentication
- **THEN** response SHALL be 401 Unauthorized

### Requirement: Audit logging with names

All station mutation endpoints SHALL log an audit entry with the station name in the command string, using the new verb names (create, delete, rename).

#### Scenario: Create station audit log

- **WHEN** admin creates station "Grill" via REST API
- **THEN** audit log SHALL contain command `station create "Grill"` with source "gui"
