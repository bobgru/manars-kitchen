## MODIFIED Requirements

### Requirement: README documents two-level help
The README SHALL include a section explaining that `help` shows command group summaries and `help <group>` shows detailed commands for that group.

#### Scenario: User reads about help system
- **WHEN** a user reads the README's CLI Features section
- **THEN** they find an explanation of two-level help with an example showing `help` and `help draft`

### Requirement: README documents compact schedule display
The README SHALL mention `draft view-compact <id>` and
`calendar view-compact <start> <end>` as alternatives to the wide table view,
suitable for narrow terminals.

#### Scenario: User reads about compact display
- **WHEN** a user reads the README's review section or CLI Features section
- **THEN** they find `draft view-compact` and `calendar view-compact` listed as options
- **AND** they find no reference to `schedule view-compact`
