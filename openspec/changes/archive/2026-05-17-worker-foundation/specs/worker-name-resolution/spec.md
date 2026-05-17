## ADDED Requirements

### Requirement: Resolve worker name to WorkerId
The system SHALL provide a name-to-`WorkerId` resolution path used by the new worker view/deactivate/activate/delete commands and their REST endpoints. The name SHALL be matched against `users.username`. The resolved `WorkerId` SHALL be `userIdToWorkerId users.id`. Resolution SHALL distinguish three error categories: (1) user not found; (2) user exists but `worker_status = 'none'` (not a worker); (3) user is a worker (`worker_status` ∈ {`active`, `inactive`}). The same resolver is used by every name-based worker command.

#### Scenario: Resolve an active worker
- **WHEN** the system resolves worker name `alice` and `alice` has `worker_status = 'active'` with `users.id = 7`
- **THEN** the resolution returns `WorkerId 7`

#### Scenario: Resolve an inactive worker
- **WHEN** the system resolves worker name `alice` and `alice` has `worker_status = 'inactive'`
- **THEN** the resolution returns the WorkerId; the caller decides whether the operation is valid for an inactive worker (e.g., `worker view` and `worker activate` are; `worker deactivate` reports already-inactive)

#### Scenario: Resolve a non-worker user
- **WHEN** the system resolves worker name `bob` and `bob` has `worker_status = 'none'`
- **THEN** the resolution returns a "not a worker" error distinct from not-found

#### Scenario: Resolve a non-existent username
- **WHEN** the system resolves worker name `ghost` and no user with that name exists
- **THEN** the resolution returns a not-found error

#### Scenario: WorkerId equals UserId at the integer level
- **WHEN** a user is created via `user create alice secret normal`
- **THEN** the user's `WorkerId` integer value equals their `UserId` integer value; no separate worker_id column is allocated
