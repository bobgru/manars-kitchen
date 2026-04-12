## ADDED Requirements

### Requirement: Skills endpoint
The system SHALL expose `GET /api/skills` returning a JSON array of `(SkillId, Skill)` pairs.

#### Scenario: Empty database returns empty list
- **WHEN** the database has no skills
- **AND** a GET request is made to `/api/skills`
- **THEN** the response is `200` with body `[]`

### Requirement: Stations endpoint
The system SHALL expose `GET /api/stations` returning a JSON array of `(Int, String)` pairs (station ID and name).

#### Scenario: Empty database returns empty list
- **WHEN** the database has no stations
- **AND** a GET request is made to `/api/stations`
- **THEN** the response is `200` with body `[]`

### Requirement: Shifts endpoint
The system SHALL expose `GET /api/shifts` returning a JSON array of shift definitions.

#### Scenario: Empty database returns empty list
- **WHEN** the database has no shifts
- **AND** a GET request is made to `/api/shifts`
- **THEN** the response is `200` with body `[]`

### Requirement: Schedules list endpoint
The system SHALL expose `GET /api/schedules` returning a JSON array of schedule names.

#### Scenario: Empty database returns empty list
- **WHEN** the database has no schedules
- **AND** a GET request is made to `/api/schedules`
- **THEN** the response is `200` with body `[]`

### Requirement: Schedule get endpoint
The system SHALL expose `GET /api/schedules/:name` returning the schedule for the given name, or 404 if not found.

#### Scenario: Missing schedule returns 404
- **WHEN** no schedule named "nonexistent" exists
- **AND** a GET request is made to `/api/schedules/nonexistent`
- **THEN** the response is `404` with a JSON error body

### Requirement: Schedule delete endpoint
The system SHALL expose `DELETE /api/schedules/:name` which deletes the named schedule and returns 204.

### Requirement: Drafts list endpoint
The system SHALL expose `GET /api/drafts` returning a JSON array of draft info objects.

#### Scenario: Empty database returns empty list
- **WHEN** the database has no drafts
- **AND** a GET request is made to `/api/drafts`
- **THEN** the response is `200` with body `[]`

### Requirement: Draft create endpoint
The system SHALL expose `POST /api/drafts` accepting a JSON body with `dateFrom` and `dateTo` fields, returning the new draft ID on success or 409 if overlapping.

#### Scenario: Create and retrieve a draft
- **WHEN** a POST is made with `{"dateFrom": "2026-05-04", "dateTo": "2026-05-10"}`
- **THEN** the response is `200` with `{"id": <int>}`
- **AND** a GET to `/api/drafts/<id>` returns the draft info

#### Scenario: Overlapping draft returns 409
- **WHEN** a draft exists for a date range
- **AND** a POST is made with an overlapping date range
- **THEN** the response is `409`

### Requirement: Draft get endpoint
The system SHALL expose `GET /api/drafts/:id` returning draft info or 404.

#### Scenario: Missing draft returns 404
- **WHEN** no draft with ID 999 exists
- **AND** a GET request is made to `/api/drafts/999`
- **THEN** the response is `404`

### Requirement: Draft generate endpoint
The system SHALL expose `POST /api/drafts/:id/generate` accepting a JSON body with `workerIds`, running the scheduler, and returning the schedule result.

#### Scenario: Generate populates schedule
- **WHEN** a draft exists and workers/stations/skills are configured
- **AND** a POST is made to `/api/drafts/<id>/generate` with worker IDs
- **THEN** the response is `200` with a `ScheduleResult` JSON object

### Requirement: Draft commit endpoint
The system SHALL expose `POST /api/drafts/:id/commit` accepting a JSON body with `note`, moving assignments to the calendar and deleting the draft.

#### Scenario: Commit moves assignments to calendar
- **WHEN** a draft is committed with a note
- **THEN** the draft is deleted (GET returns 404)
- **AND** the calendar history has a new entry

### Requirement: Draft discard endpoint
The system SHALL expose `DELETE /api/drafts/:id` which discards the draft.

#### Scenario: Discard removes draft
- **WHEN** a draft is discarded
- **THEN** a subsequent GET for that draft returns 404

### Requirement: Calendar slice endpoint
The system SHALL expose `GET /api/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD` returning assignments in the date range.

#### Scenario: Both params required
- **WHEN** a GET is made to `/api/calendar` without both `from` and `to` params
- **THEN** the response is `400`

#### Scenario: Valid range returns assignments
- **WHEN** a GET is made with valid `from` and `to` params
- **THEN** the response is `200` with a schedule JSON array

### Requirement: Calendar history endpoint
The system SHALL expose `GET /api/calendar/history` returning a JSON array of calendar commits.

#### Scenario: Empty database returns empty list
- **WHEN** no commits have been made
- **AND** a GET request is made to `/api/calendar/history`
- **THEN** the response is `200` with body `[]`

### Requirement: Calendar commit detail endpoint
The system SHALL expose `GET /api/calendar/history/:id` returning the schedule snapshot for a given commit.

### Requirement: Pending absences endpoint
The system SHALL expose `GET /api/absences/pending` returning a JSON array of pending absence requests.

#### Scenario: Empty database returns empty list
- **WHEN** no absences have been requested
- **AND** a GET request is made to `/api/absences/pending`
- **THEN** the response is `200` with body `[]`

### Requirement: Request absence endpoint
The system SHALL expose `POST /api/absences` accepting a JSON body with `workerId`, `typeId`, `from`, and `to`, returning the new absence ID.

### Requirement: Approve absence endpoint
The system SHALL expose `POST /api/absences/:id/approve` which approves a pending absence, returning 204 on success or 404 if not found.

#### Scenario: Approve nonexistent absence returns 404
- **WHEN** no absence with ID 999 exists
- **AND** a POST is made to `/api/absences/999/approve`
- **THEN** the response is `404`

### Requirement: Reject absence endpoint
The system SHALL expose `POST /api/absences/:id/reject` which rejects a pending absence, returning 204 on success or 404 if not found.

#### Scenario: Reject nonexistent absence returns 404
- **WHEN** no absence with ID 999 exists
- **AND** a POST is made to `/api/absences/999/reject`
- **THEN** the response is `404`

### Requirement: Config endpoint
The system SHALL expose `GET /api/config` returning a JSON array of `(String, Double)` config parameter pairs.

#### Scenario: Config returns parameters
- **WHEN** a GET request is made to `/api/config`
- **THEN** the response is `200` with a non-empty array of config parameters

### Requirement: JSON error responses
All error responses (400, 404, 409, 500) SHALL return a JSON body of the form `{"error": "<message>"}` with `Content-Type: application/json`.

### Requirement: JSON serialization for domain types
The system SHALL provide ToJSON and FromJSON instances for WorkerId, StationId, SkillId, AbsenceId, AbsenceTypeId, Slot, Assignment, Schedule, Skill, ShiftDef, ScheduleResult, Unfilled, UnfilledKind, AbsenceStatus, AbsenceRequest, DraftInfo, and CalendarCommit.
