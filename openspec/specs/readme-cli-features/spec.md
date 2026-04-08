## ADDED Requirements

### Requirement: README documents two-level help
The README SHALL include a section explaining that `help` shows command group summaries and `help <group>` shows detailed commands for that group.

#### Scenario: User reads about help system
- **WHEN** a user reads the README's CLI Features section
- **THEN** they find an explanation of two-level help with an example showing `help` and `help schedule`

### Requirement: README documents name-based entity references
The README SHALL include a section explaining that commands accept entity names in addition to numeric IDs, with examples showing both forms.

#### Scenario: User reads about name-based references
- **WHEN** a user reads the README's CLI Features section
- **THEN** they find an example like `worker grant-skill marco grill` alongside the numeric equivalent `worker grant-skill 2 1`

### Requirement: README documents session context
The README SHALL include a section explaining `use <type> <name>`, `context view`, `context clear`, and the `.` dot-placeholder.

#### Scenario: User reads about session context
- **WHEN** a user reads the README's CLI Features section
- **THEN** they find a workflow example showing `use worker marco`, then `worker set-hours . 40`

### Requirement: README documents compact schedule display
The README SHALL mention `schedule view-compact <name>` as an alternative to the wide table view, suitable for narrow terminals.

#### Scenario: User reads about compact display
- **WHEN** a user reads the README's review section or CLI Features section
- **THEN** they find `schedule view-compact` listed as an option

### Requirement: README documents checkpoint system
The README SHALL include a section explaining `checkpoint create`, `checkpoint commit`, `checkpoint rollback`, and `checkpoint list`.

#### Scenario: User reads about checkpoints
- **WHEN** a user reads the README's CLI Features section
- **THEN** they find an example workflow: create checkpoint, make changes, rollback or commit

### Requirement: README documents demo auto-export
The README SHALL note that demo mode automatically exports `demo-export.json` on completion and that it can be imported into an interactive session.

#### Scenario: User reads about demo export
- **WHEN** a user reads the README's demo section
- **THEN** they find that demo produces `demo-export.json` which can be imported via `import demo-export.json`

### Requirement: README project structure includes CLI/Resolve.hs
The project structure tree SHALL include the `CLI/Resolve.hs` module with a brief description.

#### Scenario: User reads project structure
- **WHEN** a user reads the project structure section
- **THEN** they see `CLI/Resolve.hs` listed with description "Entity name resolution, session context"
