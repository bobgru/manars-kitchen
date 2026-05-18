## ADDED Requirements

### Requirement: API client module for workers

The system SHALL provide `web/src/api/workers.ts` with functions:
- `fetchWorkers(status: "active" | "inactive" | "all"): Promise<WorkerSummary[]>` — GET /api/workers?status=...
- `fetchWorkerProfile(name: string): Promise<WorkerProfile>` — GET /api/workers/:name
- `renameWorker(name: string, newName: string): Promise<void>` — PUT /api/users/:id (resolves id from name)
- `deactivateWorker(name: string): Promise<{ ok: true } | { ok: false; impact: DeactivationImpact }>` — PUT /api/workers/:name/deactivate; 204 → ok, 409 → impact
- `forceDeactivateWorker(name: string): Promise<DeactivationImpact>` — PUT /api/workers/:name/deactivate/force
- `activateWorker(name: string): Promise<void>` — PUT /api/workers/:name/activate
- `deleteWorker(name: string): Promise<{ ok: true } | { ok: false; references: WorkerReferences }>` — DELETE /api/workers/:name
- `forceDeleteWorker(name: string): Promise<void>` — DELETE /api/workers/:name/force
- `createUser(req: CreateUserReq): Promise<void>` — POST /api/users (accepts `noWorker?: boolean`)

All functions SHALL use the existing `apiFetch` wrapper.

#### Scenario: API client uses name-based endpoints
- **WHEN** `deactivateWorker("alice")` is called
- **THEN** it SHALL send `PUT /api/workers/alice/deactivate`

#### Scenario: Deactivate distinguishes 204 from 409
- **WHEN** the server returns 204 from `PUT /api/workers/:name/deactivate`
- **THEN** the function SHALL resolve to `{ ok: true }`; **WHEN** the server returns 409 with a JSON body, the function SHALL resolve to `{ ok: false, impact: ... }`

### Requirement: Workers list page

Route `/workers` SHALL display a table of workers with columns: Name, Role, Status, Temp, Weekend-only, Seniority. Worker names SHALL link to the detail page at `/workers/:name`.

#### Scenario: Workers table display
- **WHEN** user navigates to `/workers`
- **THEN** a table is shown with workers matching the current status filter, names linking to detail pages, and the listed columns

#### Scenario: Empty state
- **WHEN** no workers match the current filter
- **THEN** the page SHALL display a "No workers" message that mentions the active filter value

### Requirement: Status filter on workers list

The list page SHALL include a filter control with three options: "Active", "Inactive", "All". The filter value SHALL be bound to the URL query parameter `?status=`. The default SHALL be `active`. Changing the filter SHALL update the URL and re-fetch from `GET /api/workers?status=...`.

#### Scenario: Default filter shows active workers
- **WHEN** user navigates to `/workers` with no query string
- **THEN** the page SHALL fetch `/api/workers?status=active` and display only active workers

#### Scenario: Filter is URL-linkable
- **WHEN** user navigates to `/workers?status=inactive` directly
- **THEN** the page SHALL fetch inactive workers and the filter control SHALL reflect "Inactive"

#### Scenario: Changing the filter updates the URL
- **WHEN** user changes the filter from "Active" to "All"
- **THEN** the URL SHALL update to `/workers?status=all` and the list SHALL refetch

### Requirement: Create buttons on workers list

The workers list page SHALL include two buttons: `[New Worker]` and `[New User (no worker)]`. Both buttons SHALL open the same form with fields for username, password, and role. `[New Worker]` SHALL submit to `POST /api/users` with `noWorker: false` (or omitted). `[New User (no worker)]` SHALL submit with `noWorker: true`.

#### Scenario: Create a new worker
- **WHEN** user clicks `[New Worker]`, fills in username "carol", password, and role, and submits
- **THEN** the form SHALL POST to `/api/users` without the `noWorker` flag, the form SHALL close, and the workers list SHALL refresh

#### Scenario: Create a non-worker user
- **WHEN** user clicks `[New User (no worker)]`, fills in the form, and submits
- **THEN** the form SHALL POST to `/api/users` with `noWorker: true`, and the new user SHALL NOT appear in the workers list (status defaults to `none`)

#### Scenario: Create with duplicate username
- **WHEN** user submits a username that already exists
- **THEN** the form SHALL display the error message from the server response and remain open

### Requirement: Per-row actions on workers list

Each row SHALL display action buttons appropriate to the worker's status:
- Status `active`: `[Deactivate]` `[Delete]`
- Status `inactive`: `[Activate]` `[Delete]`

#### Scenario: Activate an inactive worker
- **WHEN** user clicks `[Activate]` on an inactive worker row
- **THEN** the system SHALL call `PUT /api/workers/:name/activate` and refresh the list

#### Scenario: Activate is a single click without confirmation
- **WHEN** user clicks `[Activate]`
- **THEN** the action SHALL commit immediately; no confirmation modal SHALL be shown

### Requirement: Deactivate-with-preview flow

Clicking `[Deactivate]` SHALL call `PUT /api/workers/:name/deactivate`. If the response is `204 No Content`, the UI SHALL refresh the list and show a "Deactivated" toast. If the response is `409 Conflict` with a JSON body containing `pinsRemoved`, `draftsRemoved`, `calendarRemoved`, the UI SHALL display a modal showing the counts and offer `[Cancel]` and `[Deactivate Anyway]` buttons. Clicking `[Deactivate Anyway]` SHALL call `PUT /api/workers/:name/deactivate/force` and refresh on success.

#### Scenario: Deactivate worker with no impact
- **WHEN** the user clicks `[Deactivate]` on a worker with zero pins, drafts, and future calendar entries
- **THEN** the server returns 204 and the UI refreshes the list with a success toast; no modal is shown

#### Scenario: Deactivate worker with impact shows preview
- **WHEN** the user clicks `[Deactivate]` on a worker with 3 pins, 12 draft entries, and 8 future calendar entries
- **THEN** the server returns 409 with those counts and the UI shows a modal listing them with `[Cancel]` and `[Deactivate Anyway]`; no state change occurs server-side

#### Scenario: User confirms deactivate after preview
- **WHEN** user clicks `[Deactivate Anyway]` in the preview modal
- **THEN** the UI SHALL call `PUT /api/workers/:name/deactivate/force`, close the modal, and refresh the list

#### Scenario: User cancels deactivate after preview
- **WHEN** user clicks `[Cancel]` in the preview modal
- **THEN** the modal SHALL close and no server call SHALL be made; worker state remains unchanged

### Requirement: Delete worker from list page

Each row SHALL have a `[Delete]` button. Clicking it SHALL call `DELETE /api/workers/:name`. If the response is 204, the list refreshes. If the response is 409 with a `WorkerReferences` body, the UI SHALL display a modal listing the references with `[Cancel]` and `[Force Delete]`. Clicking `[Force Delete]` SHALL call `DELETE /api/workers/:name/force` and refresh.

#### Scenario: Delete unreferenced worker
- **WHEN** user clicks `[Delete]` on a worker with no configuration or schedule references
- **THEN** the worker is deleted (status set to `none`) and the list refreshes

#### Scenario: Delete referenced worker shows confirmation
- **WHEN** user clicks `[Delete]` on a worker with references
- **THEN** a modal SHALL display the references with `[Cancel]` and `[Force Delete]` options

### Requirement: Worker detail page (identity-only)

Route `/workers/:name` SHALL display the worker's identity section (name, status, role, userId, workerId) and read-only placeholder cards for the deferred sections (Skills, Employment, Preferences, Station Prefs, Cross-training, Pairing). The name SHALL be editable. The status SHALL be displayed alongside `[Activate]` or `[Deactivate]` buttons matching the list-page semantics.

#### Scenario: View worker detail
- **WHEN** user navigates to `/workers/alice`
- **THEN** the page shows alice's name (editable), status, role, userId, and workerId; placeholder cards display the read-only values for the other 18 profile fields

#### Scenario: Worker not found
- **WHEN** user navigates to `/workers/nonexistent`
- **THEN** the page SHALL display "Worker not found" with a link back to the list

#### Scenario: Rename worker from detail page
- **WHEN** user changes the name from "alice" to "alice2" and clicks save
- **THEN** the system calls `PUT /api/users/:id` with the new name; the URL updates to `/workers/alice2`; the list refreshes via SSE

#### Scenario: Deactivate from detail page uses preview flow
- **WHEN** user clicks `[Deactivate]` on the detail page and the worker has nonzero impact
- **THEN** the same preview modal as the list page is shown, and confirmation calls `PUT /api/workers/:name/deactivate/force`

#### Scenario: Activate from detail page is single-click
- **WHEN** user clicks `[Activate]` on an inactive worker's detail page
- **THEN** the action commits immediately without confirmation

#### Scenario: Placeholder cards show read-only values
- **WHEN** the detail page renders for a worker with skills `["a", "b", "c"]`
- **THEN** the Skills card SHALL show "Skills (3) — managed via CLI for now" with the list of skill names visible read-only

### Requirement: Dual SSE subscription for worker pages

Both the workers list page and the worker detail page SHALL subscribe to SSE events with `entityType="worker"` AND `entityType="user"`. Either subscription firing SHALL trigger a re-fetch of the page's data.

#### Scenario: User rename refreshes workers list
- **WHEN** an admin runs `user rename alice alice2` from the CLI while the workers list is open
- **THEN** the SSE event with `entityType="user"` SHALL fire and the page SHALL re-fetch and display "alice2"

#### Scenario: User force-delete removes worker from list
- **WHEN** an admin runs `user force-delete <id>` against a user who is a worker
- **THEN** the SSE event SHALL fire and the workers list SHALL re-fetch, removing the row

#### Scenario: User create with no-worker flag does not add row to active filter
- **WHEN** an admin creates a non-worker user
- **THEN** the workers list (filter=active) SHALL re-fetch but the new user SHALL NOT appear

#### Scenario: Worker activate/deactivate refreshes both pages
- **WHEN** an admin runs `worker deactivate alice` from the CLI
- **THEN** the SSE event with `entityType="worker"` SHALL fire and the workers list and (if open) detail page SHALL re-fetch

### Requirement: Workers route registration

The React app SHALL register routes `/workers` (list page) and `/workers/:name` (detail page). The existing sidebar "Workers" link SHALL navigate to `/workers`.

#### Scenario: Navigate via sidebar
- **WHEN** user clicks "Workers" in the sidebar
- **THEN** the browser navigates to `/workers` and the workers list page is displayed

### Requirement: Loading and error states

The workers pages SHALL show a loading indicator while fetching data and an error message if a fetch or mutation fails.

#### Scenario: Loading state
- **WHEN** workers are being fetched
- **THEN** a loading indicator is shown

#### Scenario: Network error
- **WHEN** a fetch fails
- **THEN** an error message is displayed
