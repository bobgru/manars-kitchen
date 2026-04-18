# Proposal: Topic-Routed Pub/Sub with Typed Channels

## Problem

The GUI and CLI can both mutate state, but neither knows when the other has made a change. The skills admin page acknowledged this directly: "the GUI won't auto-refresh when the terminal makes a change (and vice versa)." Meanwhile, audit logging is baked inline at two separate call sites (CLI and RPC) with slightly different code paths, and there's no uniform way for UI components to observe data changes.

The existing `PubSub e` bus was designed for progress events — it delivers every event to every subscriber with no routing. To support UI refresh, terminal echo, and audit logging as independent subscribers reacting to domain events, the bus needs topic-based routing with regex matching.

## Solution

Evolve the pub/sub system from a flat typed bus to topic-routed typed channels, and use command events as the first new channel to unify audit logging with UI observation.

### Topic-routed bus

Replace `PubSub e` with `TopicBus e` — same typed, in-process, MVar-protected design, but subscribers register with a regex pattern and receive `(Topic, e)` pairs. Only matching events are delivered.

Topic schema: `<domain>.<command>.<id>` — e.g., `skill.create.4`, `absence.request.3`, `draft.commit.7`. The domain is the entity type, the command is the operation, and the ID is the affected entity. Specificity grows left to right; most subscribers match on a prefix (`skill\..*`) and ignore the ID.

### Typed channels via AppBus

A container record holds multiple `TopicBus` values, one per event type:

```
AppBus
├── busCommands :: TopicBus CommandEvent    -- domain mutations
└── busProgress :: TopicBus ProgressEvent   -- optimizer/long-running ops
```

Each channel is fully typed. Adding a new event type in the future means adding one field to `AppBus` — no sum type cases to update, no existing subscribers to modify.

### CommandEvent payload

```
CommandEvent
├── ceCommand   :: String       -- human-readable command text ("skill create 4 grill")
├── ceMeta      :: CommandMeta  -- structured fields (entity_type, operation, ids, dates, params)
├── ceSource    :: Source        -- CLI | RPC | Demo
└── ceUsername  :: String        -- who did it
```

The topic carries routing information (what changed). The payload carries consumption information (the full context for audit, terminal echo, and UI filtering). The overlap between topic and payload is intentional — routing and consumption serve different purposes.

### Audit logging as a subscriber

The two inline audit log writes (CLI's `repoLogCommand` and RPC's `logRpc`) are replaced by a single audit subscriber registered on `busCommands` with pattern `.*`. The subscriber writes the audit row from the `CommandEvent` payload. One code path, one log format, regardless of source.

### Active-listener guard

A listener must not react to events it caused — otherwise the terminal would echo its own commands back to itself, and the web UI would refetch in response to its own mutations. Each subscriber filters on `ceSource` in the payload:

- **Terminal echo**: skips events where `ceSource == CLI` (I caused this)
- **Web UI refresh**: skips events where `ceSource == RPC` (I caused this)
- **Audit writer**: logs everything regardless of source

This works because each source only ignores events from its own transport. Events from the *other* source, or from any future third source (scheduled jobs, external API callers), are always delivered.

If the web UI later has multiple independent pages that can mutate, a more granular source identity (e.g., `RPC SessionId`) would let page A refresh when page B mutates without suppressing its own events. For now, with one CLI session and one web session, `CLI | RPC` is sufficient.

### Subscribers

| Subscriber | Channel | Pattern | Source filter | Consumes |
|---|---|---|---|---|
| Audit writer | busCommands | `.*` | none | Full payload → audit_log row |
| Terminal echo | busCommands | `.*` | skip CLI | `ceCommand` → print to terminal |
| Web UI (skills page) | busCommands | `skill\..*` | skip RPC | Signal to refetch |
| Web UI (future pages) | busCommands | `station\..*` etc. | skip RPC | Signal to refetch |

### Skill create/rename fix

As a prerequisite, fix the `INSERT OR REPLACE` semantics on skill creation: reject `skill create` when the ID already exists, and wire up an explicit `skill rename <id> <new-name>` CLI command (the repo layer `repoRenameSkill` already exists). This ensures the pub/sub topics accurately reflect the real operation (create vs rename), and the command string echoed to the terminal is honest.

### Layout

```
┌──────────┐     ┌──────────┐
│   CLI    │     │  Web UI  │
│ (command)│     │ (action) │
└────┬─────┘     └────┬─────┘
     │                 │
     ▼                 ▼
┌──────────────────────────────┐
│     Service layer            │
│  build CommandEvent + Topic  │
│  publish on busCommands      │
└──────────────┬───────────────┘
               │
     ┌─────────┼──────────┐
     ▼         ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│ Audit  │ │Terminal│ │Web UI  │
│ Writer │ │ Echo   │ │Refresh │
└────────┘ └────────┘ └────────┘
```

## Not in scope

- **Thread-safe terminal output** (high priority) — an MVar-protected write function that serializes all stdout access, preventing interleaved output from concurrent threads (terminal echo, optimizer progress, command output). Should be the immediate follow-up to this change.
- **Graphical demo via pub/sub** — the demo script becomes a third event source (`ceSource = Demo`) that executes real commands and publishes `CommandEvent`s. The terminal echoes the commands, the web UI animates live as entities are created and schedules are built. This replaces the current terminal-only demo with a full graphical experience using no special rendering code — just the same subscriber infrastructure. Depends on this change for the bus and on SSE/WebSocket for pushing events to the browser. Tracked as a future change.
- **SSE/WebSocket bridge** for pushing events to the browser in real time — the web UI will poll or refetch on user interaction for now; real-time push is a follow-up
- **Progress event migration** — `busProgress` keeps the existing `ProgressEvent` type and behavior; adding topic routing to progress events is optional/future
- **Notification system** (email, SMS for absence requests, etc.) — the bus supports this pattern but wiring notifications is a separate change
- **Web UI create/delete skills** — the GUI currently only supports rename and implications; adding create/delete forms is a separate change

## Risks

- **Audit reliability**: Moving audit logging from inline writes to a subscriber means a bug in the pub/sub bus could silently drop audit entries. Mitigation: the bus is simple and well-tested; the audit subscriber is the first one registered and runs synchronously. If this proves fragile, we can add a fallback or revert to inline-plus-publish.
- **Regex compilation cost**: Compiling regexes on every publish could be slow if subscriber count grows. Mitigation: pre-compile patterns at subscription time and match against compiled regexes. Subscriber counts will remain small (single digits) for the foreseeable future.
- **Two-phase migration**: The existing `PubSub e` (used by the optimizer) and the new `TopicBus e` need to coexist during the transition. The `AppBus` container handles this cleanly — `busProgress` can initially wrap the old `PubSub` or be a `TopicBus` where the optimizer publishes to a single topic.

## Capabilities

### New capabilities
- `topic-bus`: Topic-routed typed pub/sub bus with regex-matched subscriptions
- `app-bus`: Application-level container holding typed channels (commands, progress)
- `command-events`: CommandEvent type and publishing from the service layer
- `audit-subscriber`: Audit log writer as a bus subscriber
- `skill-rename-command`: CLI command for renaming skills

### Modified capabilities
- `pub-sub-bus`: Evolves from flat delivery to topic-routed delivery
- `command-classifier`: CommandMeta reused as part of CommandEvent payload
- `skill creation`: Rejects duplicate IDs instead of silent upsert
