## ADDED Requirements

### Requirement: Command input
The terminal SHALL provide a text input field where the user can type a command and press Enter to execute it.

#### Scenario: Execute a command
- **WHEN** the user types `skill list` and presses Enter
- **THEN** the terminal sends the command to `/rpc/execute`
- **AND** displays the command as an input line in the scrollback (prefixed with `>`)
- **AND** displays the response text below it
- **AND** clears the input field for the next command

#### Scenario: Empty input
- **WHEN** the user presses Enter with an empty input field
- **THEN** no request is made and the input field remains focused

### Requirement: Scrollback output
The terminal SHALL display a scrollable history of commands and their output.

#### Scenario: Multiple commands
- **WHEN** the user executes several commands in sequence
- **THEN** all commands and their outputs are visible in the scrollback in chronological order

#### Scenario: Auto-scroll
- **WHEN** new output appears
- **THEN** the terminal scrolls to show the most recent output

### Requirement: Command history
The terminal SHALL maintain an in-memory history of previously entered commands, navigable with arrow keys.

#### Scenario: Navigate history with up arrow
- **WHEN** the user presses the up arrow key
- **THEN** the input field is populated with the previous command

#### Scenario: Navigate forward with down arrow
- **WHEN** the user has navigated back in history and presses the down arrow key
- **THEN** the input field is populated with the next command in history (or cleared if at the end)

#### Scenario: History is per-tab
- **WHEN** the user opens two browser tabs
- **THEN** each tab maintains its own independent command history

### Requirement: Multi-line command input
The terminal SHALL allow the user to paste multi-line text to execute multiple commands in sequence.

#### Scenario: Paste multiple commands
- **WHEN** the user pastes text containing multiple lines (e.g., copied from a script)
- **THEN** each non-empty line is executed as a separate command in order
- **AND** all commands and outputs appear in the scrollback

### Requirement: Loading indicator
The terminal SHALL indicate when a command is being executed.

#### Scenario: Slow command
- **WHEN** a command takes more than a moment to return
- **THEN** the terminal shows a visual indicator that the command is in progress
- **AND** the input field is disabled until the response arrives
