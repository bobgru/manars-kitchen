## ADDED Requirements

### Requirement: Foreign key constraints on skill_id columns

The database schema SHALL declare `REFERENCES skills(id)` on all columns that reference skill IDs: `skill_implications.skill_id`, `skill_implications.implies_skill_id`, `worker_skills.skill_id`, `station_required_skills.skill_id`, and `worker_cross_training.skill_id`.

#### Scenario: Insert with valid skill ID succeeds

- **WHEN** inserting a row into `worker_skills` with a `skill_id` that exists in the `skills` table
- **THEN** the insert succeeds

#### Scenario: Insert with invalid skill ID fails

- **WHEN** inserting a row into `worker_skills` with a `skill_id` that does not exist in the `skills` table
- **THEN** the insert fails with a foreign key constraint violation

#### Scenario: Direct skill deletion blocked by FK

- **WHEN** a raw `DELETE FROM skills WHERE id = ?` is executed while `worker_skills` rows reference that ID
- **THEN** the delete fails with a foreign key constraint violation
