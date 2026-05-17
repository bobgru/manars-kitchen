# User Rename

Provides `user rename <old> <new>` to update a user's username. Because worker name equals username, this is also the only way to rename a worker.

## Requirements

### Requirement: Rename a user by username
The system SHALL provide `user rename <old> <new>` that updates `users.username` from `<old>` to `<new>`. Because worker name = username, this command is also the way to rename a worker. The system SHALL reject the rename if `<new>` already exists as a username, and SHALL reject if `<old>` does not match an existing user.

#### Scenario: Successful rename
- **WHEN** an admin runs `user rename alice alicia`
- **THEN** the user previously known as `alice` has username `alicia`, all foreign-key references (sessions, audit log entries) continue to point at the same user id, and `worker view alicia` returns the renamed worker's profile

#### Scenario: Rename with collision
- **WHEN** an admin runs `user rename alice bob` and `bob` already exists
- **THEN** the system rejects the rename and prints an error message identifying the collision; no change is made

#### Scenario: Rename non-existent user
- **WHEN** an admin runs `user rename ghost alicia` and no user named `ghost` exists
- **THEN** the system rejects the rename with a not-found error

#### Scenario: REST rename endpoint
- **WHEN** an admin sends `PUT /api/users/:id/rename` with body `{"name":"alicia"}`
- **THEN** the user with id `:id` has username `alicia`, and the response indicates success

#### Scenario: Audit log records rename
- **WHEN** an admin runs `user rename alice alicia`
- **THEN** an audit entry is logged with operation `rename`, entity type `user`, entity id of the user, and command string `user rename alice alicia`
