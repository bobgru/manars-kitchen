## ADDED Requirements

### Requirement: User delete is safe by default; force-delete cascades
The system SHALL change `user delete <id>` to a safe-delete operation. If the user has `worker_status` ∈ {`active`, `inactive`}, the system SHALL block the delete and tell the operator to use `worker delete` (or `worker force-delete`) first. The system SHALL provide `user force-delete <id>` that cascades: removes all `worker_*` configuration and worker-keyed schedule/history rows, then deletes the user.

#### Scenario: Delete a non-worker user
- **WHEN** an admin runs `user delete <id>` for a user with `worker_status = 'none'`
- **THEN** the user is deleted; no other rows are affected

#### Scenario: Safe delete blocks active worker user
- **WHEN** an admin runs `user delete <id>` for a user whose `worker_status = 'active'`
- **THEN** the system blocks the delete and prints a message instructing the operator to run `worker delete <name>` (or `worker force-delete <name>`) first; no changes are made

#### Scenario: Safe delete blocks inactive worker user
- **WHEN** an admin runs `user delete <id>` for a user whose `worker_status = 'inactive'`
- **THEN** the system blocks the delete and prints a message instructing the operator to run `worker delete <name>` first; no changes are made

#### Scenario: Force-delete cascades a worker user
- **WHEN** an admin runs `user force-delete <id>` for an active worker user with assignments and worker_skills rows
- **THEN** the system removes all `worker_*` rows and worker-keyed schedule/history rows for the worker_id, then deletes the user

#### Scenario: Force-delete a non-worker user
- **WHEN** an admin runs `user force-delete <id>` for a user with `worker_status = 'none'`
- **THEN** the user is deleted; no `worker_*` rows are scanned (none reference this user)

#### Scenario: REST safe delete returns 409 when user is a worker
- **WHEN** an admin sends `DELETE /api/users/:id` for a worker user
- **THEN** the system returns HTTP 409 with a body indicating the user is a worker and pointing at the worker delete endpoints

#### Scenario: REST force delete cascades
- **WHEN** an admin sends `DELETE /api/users/:id/force`
- **THEN** the system cascades the deletion and returns 204

#### Scenario: Audit log records the operation
- **WHEN** any of the above delete operations succeeds
- **THEN** an audit entry is logged with the appropriate operation (`delete` or `force-delete`) and entity type `user`
