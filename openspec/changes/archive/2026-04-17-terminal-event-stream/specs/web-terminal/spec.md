## MODIFIED Requirements

### Requirement: Scrollback output
The terminal SHALL display a scrollable history of commands, their output, and echoed GUI events.

#### Scenario: Multiple commands
- **WHEN** the user executes several commands in sequence
- **THEN** all commands and their outputs are visible in the scrollback in chronological order

#### Scenario: Auto-scroll
- **WHEN** new output appears (including echoed events)
- **THEN** the terminal scrolls to show the most recent output

## ADDED Requirements

### Requirement: Echo output line type
The `OutputLine` type SHALL include an `"echo"` discriminator alongside `"command"`, `"output"`, and `"error"`. Echo lines represent GUI-originated commands received via SSE.

#### Scenario: Echo line in scrollback
- **WHEN** a GUI event is received via SSE
- **THEN** a line with `type: "echo"` and the command text is appended to the scrollback

### Requirement: EventSource connection
The terminal component SHALL open an `EventSource` connection to `/api/events?token=<session-token>` when the user is authenticated. The connection SHALL be closed on component unmount or session expiry.

#### Scenario: Connection on login
- **WHEN** the user logs in and the terminal component mounts
- **THEN** an `EventSource` is opened to `/api/events` with the session token

#### Scenario: Cleanup on unmount
- **WHEN** the terminal component unmounts
- **THEN** the `EventSource` connection is closed

#### Scenario: Auto-reconnect on disconnect
- **WHEN** the SSE connection drops unexpectedly
- **THEN** the browser's built-in `EventSource` auto-reconnect re-establishes the connection

### Requirement: Echoed command display
Echoed GUI events SHALL be displayed in the terminal scrollback with a visual prefix (e.g., `[echo]`) and a distinct color to distinguish them from typed commands.

#### Scenario: Echoed event appearance
- **WHEN** a GUI event `skill rename grill broiler` is received via SSE
- **THEN** the terminal displays `[echo] skill rename grill broiler` in light blue (`#5390d9`)

#### Scenario: Typed command appearance
- **WHEN** the user types and submits a command
- **THEN** the command is displayed in bright white (`#ffffff`) prefixed with `>`

### Requirement: Echo color scheme
The terminal SHALL use the following color scheme:
- Typed commands (prefixed with `>`): bright white (`#ffffff`)
- Echoed GUI events (prefixed with `[echo]`): light blue (`#5390d9`)
- Command output: light gray (`#e0e0e0`)
- Prompt character: light blue (`#5390d9`)

#### Scenario: Color distinction
- **WHEN** the scrollback contains both typed commands and echoed events
- **THEN** they are visually distinguishable by color (white vs. light blue)
