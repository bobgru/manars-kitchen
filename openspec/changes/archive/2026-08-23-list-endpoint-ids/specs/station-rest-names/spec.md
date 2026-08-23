## MODIFIED Requirements

### Requirement: List stations returns Station objects

`GET /api/stations` SHALL return a JSON array of station objects with `id`, `name`,
`minStaff`, and `maxStaff` fields. The `id` is the station's storage identifier, present so
that clients can resolve the numeric `station` field of an `Assignment` to a name; it SHALL
NOT be used to address a station in any request path or body — every station mutation
endpoint remains name-addressed.

#### Scenario: List stations response format

- **WHEN** client sends `GET /api/stations`
- **THEN** response SHALL be `[{"id": 1, "name": "Grill", "minStaff": 1, "maxStaff": 2}, ...]`

#### Scenario: Listed id matches the id used in assignments

- **WHEN** a calendar assignment names station id 3 and `GET /api/stations` reports
  `{"id": 3, "name": "Grill", ...}`
- **THEN** the client SHALL be able to render that assignment's station as "Grill" without
  consulting any other endpoint
