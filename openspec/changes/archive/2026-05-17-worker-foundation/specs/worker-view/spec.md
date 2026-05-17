## ADDED Requirements

### Requirement: Display a worker's full profile
The system SHALL provide `worker view <name>` that resolves `<name>` (= username) to a `WorkerId` and displays the worker's complete profile in the CLI. The profile SHALL include: name, worker_id, role, status (`active` or `inactive`), `deactivated_at` (when status is `inactive`), employment status (overtime model, pay period tracking, temp flag), max period hours, overtime opt-in flag, weekend-only flag, prefers-variety flag, station preferences (in order, by station name), shift preferences, seniority level, cross-training goals (skill names), avoid-pairing list (worker names), prefer-pairing list (worker names), and granted skills (skill names). Empty sections SHALL be displayed with an explicit indicator rather than omitted. The command SHALL succeed for both `active` and `inactive` workers.

#### Scenario: View an active worker with full configuration
- **WHEN** an admin runs `worker view alice` for an active worker with skills, employment, prefs, and pairings configured
- **THEN** the system prints all profile sections including `Status: active`, with skill and station names rather than IDs

#### Scenario: View an active worker with default configuration
- **WHEN** an admin runs `worker view alice` for a freshly created worker with no extra configuration
- **THEN** the system prints `Status: active`, employment defaults (eligible / standard / not temp), and explicit indicators for empty sections (e.g., "No station preferences", "No skills granted")

#### Scenario: View an inactive worker
- **WHEN** an admin runs `worker view alice` for a worker with `worker_status = 'inactive'`
- **THEN** the system prints `Status: inactive` and `Deactivated: <ISO date>` and shows the preserved configuration

#### Scenario: View a non-worker user
- **WHEN** an admin runs `worker view bob` and `bob` is a user with `worker_status = 'none'`
- **THEN** the system prints an error indicating that `bob` is not a worker

#### Scenario: View a non-existent name
- **WHEN** an admin runs `worker view ghost` and no user named `ghost` exists
- **THEN** the system prints a not-found error

#### Scenario: REST GET /api/workers/:name for an active worker
- **WHEN** an admin GETs `/api/workers/alice`
- **THEN** the system returns 200 with a JSON body containing the same fields as the CLI display, with skill and station names as text and `status` as `"active"`

#### Scenario: REST GET /api/workers/:name for an inactive worker
- **WHEN** an admin GETs `/api/workers/alice` where alice is inactive
- **THEN** the system returns 200 with `status: "inactive"` and `deactivatedAt` populated

#### Scenario: REST GET /api/workers/:name for a non-worker user returns 404
- **WHEN** an admin GETs `/api/workers/bob` and `bob` has `worker_status = 'none'`
- **THEN** the system returns 404
