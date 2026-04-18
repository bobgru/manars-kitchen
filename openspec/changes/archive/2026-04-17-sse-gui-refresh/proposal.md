# SSE-Driven GUI Refresh

## Problem

The existing SSE infrastructure only flows in one direction: GUI actions echo
into the terminal pane. When a user types a command in the terminal (e.g.,
`skill rename 1 broiler`), GUI components like the skills list page remain
stale until manually navigated away and back. Two problems cause this:

1. **EventStream.hs filters `ceSource == GUI`** -- RPC-originated events
   (terminal commands) are silently dropped and never reach the browser.
2. **GUI components don't subscribe to SSE** -- they fetch data once on mount
   and only re-fetch after their own mutations.

This also means two browser tabs viewing the same data cannot stay in sync.

## Solution

Widen the SSE filter to deliver all mutation events regardless of source, and
add a shared React hook that lets GUI components subscribe to entity-specific
events and re-fetch when relevant mutations occur. Add a `clientId` to the
event protocol so the terminal can suppress echo of its own commands while
still showing commands from other sources.

### Server-side changes

**EventStream.hs filter**:
```
Current:  ceSource == GUI && ceUsername == clientUser
New:      cmIsMutation (ceMeta ev) && ceUsername == clientUser
```

Drop the source filter. Add mutation filter so read-only commands (`skill list`,
`help`, etc.) don't trigger unnecessary SSE traffic. Username filter stays for
multi-tenancy.

**`clientId` in CommandEvent**:

Add `ceClientId :: Maybe String` to `CommandEvent`. REST handlers pass
`Nothing` (no client identity needed -- GUI components refresh via their own
mutation callbacks). RPC execute passes the `clientId` from the request body.
SSE JSON includes `clientId` when present.

**`clientId` in RPC request**:

Add optional `clientId` field to `ExecuteReq`. The web terminal generates a
UUID on mount and includes it in every `/rpc/execute` request.

### Frontend shared infrastructure

**`SSEProvider` context** -- wraps the app, manages a single shared
`EventSource` connection. Parses incoming events and dispatches to registered
subscribers by entity type.

**`useEntityEvents(entityType, callback)` hook** -- components declare which
entity type they care about and provide a callback (typically their existing
`loadData` function). The hook registers/unregisters with the provider on
mount/unmount.

```
SSEProvider
  └─ Single EventSource → /api/events?token=...
     │
     ├─ event: {entityType: "skill", ...}
     │   └─ dispatches to: SkillsListPage.loadData()
     │                     SkillDetailPage.loadData()
     │
     ├─ event: {entityType: "station", ...}
     │   └─ dispatches to: (future station pages)
     │
     └─ event: {entityType: "worker", ...}
         └─ dispatches to: (future worker pages)
```

### Terminal changes

**Terminal.tsx**:
- Generates `clientId` via `crypto.randomUUID()` on mount
- Includes `clientId` in `/rpc/execute` requests
- Ignores SSE events where `event.clientId === myClientId` (suppress self-echo)
- Continues echoing GUI events and other clients' terminal commands

### SSE JSON payload

```json
{
  "command": "skill rename 1 broiler",
  "source": "GUI",
  "entityType": "skill",
  "operation": "rename",
  "entityId": 1,
  "isMutation": true,
  "clientId": "abc-123"
}
```

Fields `entityType`, `operation`, `entityId` are extracted from the existing
`CommandMeta` on the server side. The frontend uses `entityType` for
dispatching and `clientId` for self-echo suppression.

## What comes free

- **Multi-tab sync**: two tabs open, mutation in one refreshes the other
- **GUI <-> terminal sync**: both directions work
- **Terminal <-> terminal sync**: multiple terminal panes stay in sync
- **Selective refresh**: only pages caring about the mutated entity re-fetch

## Key Design Decisions

1. **One shared EventSource, not one per component** -- avoids connection
   proliferation and makes cleanup predictable.

2. **Entity-type dispatch, not topic regex on the client** -- the server
   already classifies events via `CommandMeta`. Sending structured fields
   (`entityType`, `operation`, `entityId`) is simpler than having the
   frontend parse topic strings or compile regexes.

3. **`clientId` for self-echo suppression** -- more robust than source-based
   filtering. A terminal ignores only its own events, not all RPC events.
   This means Terminal A sees Terminal B's commands, enabling multi-terminal
   awareness.

4. **Mutation filter on the server** -- `cmIsMutation` is already computed by
   `CommandMeta.classify`. Filtering server-side avoids sending read-only
   events over the wire.

## Out of Scope

- Optimistic UI updates (components still re-fetch on event; no client-side
  state patching)
- Streaming output for long-running commands (optimizer progress)
- Debouncing rapid mutations (re-fetch per event is fine at admin-rate
  operation volume)
- Ticket-based SSE auth (noted in the terminal-event-stream change as future
  hardening)
