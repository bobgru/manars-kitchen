## MODIFIED Requirements

### Requirement: Delete hint session on draft commit or discard
The system SHALL delete every persisted hint session associated with a draft when
that draft is committed or discarded — not only the session belonging to the
caller. Cleanup SHALL happen in `Service.Draft`, so that a commit or discard over
REST cleans up exactly as a CLI one does.

#### Scenario: Draft commit cleans up hint session
- **WHEN** draft 1 has a persisted hint session and the user runs `draft commit 1`
- **THEN** the hint session row for draft 1 is deleted

#### Scenario: Draft discard cleans up hint session
- **WHEN** draft 1 has a persisted hint session and the user runs `draft discard 1`
- **THEN** the hint session row for draft 1 is deleted

#### Scenario: Another session's saved hints are cleaned up too
- **WHEN** two CLI sessions each saved a hint session for draft 1 and one of them commits draft 1
- **THEN** both hint session rows for draft 1 are deleted, leaving no row pointing at a draft that no longer exists

#### Scenario: In-memory session is cleared alongside the row
- **WHEN** the user's active hint session belongs to draft 1 and the user commits draft 1
- **THEN** the persisted row is deleted by the service
- **AND** the CLI clears its in-memory hint session, which the service cannot see
