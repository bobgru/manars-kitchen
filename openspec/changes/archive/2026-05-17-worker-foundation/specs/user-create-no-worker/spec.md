## ADDED Requirements

### Requirement: User create supports non-worker accounts
The system SHALL accept an optional `--no-worker` flag on `user create <name> <pass> <role>` that creates a user with `worker_status = 'none'`. Without the flag, the existing default behavior is preserved: the user is created with `worker_status = 'active'` and is treated as a worker. The system SHALL NOT allocate a separate `worker_id`; a worker's `WorkerId` is the same integer as their `UserId`.

#### Scenario: Default user create produces an active worker
- **WHEN** an admin runs `user create alice secret normal`
- **THEN** the system creates a user named `alice` with role `normal` and `worker_status = 'active'`, and `worker view alice` shows the worker as active

#### Scenario: --no-worker creates a non-worker user
- **WHEN** an admin runs `user create bob secret admin --no-worker`
- **THEN** the system creates a user named `bob` with `worker_status = 'none'`, and `worker view bob` returns a "not a worker" error

#### Scenario: REST CreateUserReq accepts noWorker flag
- **WHEN** an admin POSTs `{"name":"bob","password":"secret","role":"admin","noWorker":true}` to `/api/users`
- **THEN** the system creates `bob` with `worker_status = 'none'`

#### Scenario: REST CreateUserReq omitting noWorker defaults to worker
- **WHEN** an admin POSTs `{"name":"alice","password":"secret","role":"normal"}` to `/api/users`
- **THEN** the system creates `alice` with `worker_status = 'active'`
