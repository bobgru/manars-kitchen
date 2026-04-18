# Terminal Event Stream — Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Server Process                          │
│                                                               │
│  ┌──────────┐ publish(GUI)  ┌─────────┐                      │
│  │ REST     │──────────────▶│         │───▶ Audit subscriber │
│  │ Handlers │  name-based   │ AppBus  │                      │
│  └──────────┘  command str  │(cmdBus) │───▶ SSE subscriber   │
│                             │         │     (per-connection) │
│  ┌──────────┐ publish(RPC)  │         │         │            │
│  │/rpc/exec │──────────────▶│         │         │            │
│  │(terminal)│               └─────────┘         │            │
│  └──────────┘                                   │            │
│       ▲                                         ▼            │
│       │ POST                          ┌──────────────────┐   │
│       │                               │GET /api/events   │   │
│       │                               │  ?token=xxx      │   │
│       │                               │                  │   │
│       │                               │ text/event-stream│   │
│       │                               │ data: {...}      │   │
│       │                               └────────┬─────────┘   │
└───────┼────────────────────────────────────────┼─────────────┘
        │                                        │
  ┌─────┴────────────────────────────────────────┴──┐
  │  Browser                                         │
  │                                                   │
  │  EventSource("/api/events?token=xxx")             │
  │       │                                           │
  │       ▼                                           │
  │  Terminal component                               │
  │  ┌──────────────────────────────────────────────┐ │
  │  │ > skill list                    (white)      │ │
  │  │ grill, pastry, sauté           (gray)        │ │
  │  │ [echo] skill rename grill broiler (lt blue)  │ │
  │  │ >                                            │ │
  │  └──────────────────────────────────────────────┘ │
  └───────────────────────────────────────────────────┘
```

## Component Design

### 1. `GUI` Source

Add `GUI` to the `Source` type in `Service.PubSub`:

```haskell
data Source = CLI | RPC | GUI | Demo
```

- REST handlers publish as `GUI`
- `/rpc/execute` (terminal commands) publishes as `RPC`
- Standalone CLI publishes as `CLI`
- `sourceString GUI = "gui"` for audit log

### 2. SSE Endpoint (WAI-level)

Implement the SSE endpoint as a raw WAI `Application` outside of Servant,
handled in the `spaFallback` middleware in `server-app/Main.hs`. This avoids
Servant streaming complexity and gives direct control over the response body.

**Route**: `GET /api/events?token=<session-token>`

**Auth**: Extract token from query string, validate via the same
`repoGetSessionByToken` / idle-timeout / `repoGetUser` chain used by
`authHandler`. Reject with 401 plain text if invalid.

> **Security note (query-param tokens)**: The `EventSource` browser API does
> not support custom headers, so we pass the session token as a query
> parameter. This means the token may appear in server access logs, proxy
> logs, and browser history. A safer alternative is a **ticket-based flow**:
> the client POSTs to `/api/events/ticket` with the Bearer token to receive a
> short-lived (30-second), single-use opaque ticket. The client then opens
> `EventSource("/api/events?ticket=xyz")`. The server validates and consumes
> the ticket on first use. This prevents long-lived tokens from leaking
> through URL logging. Adopt before any multi-user or public deployment.

**Response**: `Content-Type: text/event-stream`, chunked transfer encoding.
The connection stays open. Each event is formatted as:

```
data: {"command":"skill rename grill broiler","source":"gui","username":"admin"}

```

(Two newlines terminate an SSE event.)

**Lifecycle**:
1. Validate token, resolve `User` and `SessionId`
2. Subscribe to `busCommands` with pattern `".*"`
3. Filter callback: only forward events where `ceSource == GUI`
4. Write SSE-formatted JSON to the response body on each matching event
5. Send a `:keepalive` comment every 30 seconds to prevent proxy timeouts
6. On client disconnect (write fails), unsubscribe and exit

### 3. SSE Handler Module

New module: `server/Server/EventStream.hs`

```haskell
module Server.EventStream (eventStreamApp) where

eventStreamApp :: Repository -> AppBus -> Application
```

Takes `Repository` (for token validation) and `AppBus` (for subscribing).
Returns a WAI `Application` that handles the `/api/events` path.

### 4. Server Wiring

In `server-app/Main.hs`, pass `execEnv` to a modified `spaFallback` that
intercepts `/api/events`:

```
spaFallback:
  /api/events  → eventStreamApp repo (eeBus execEnv)
  /api/*       → servantApp
  /rpc/*       → servantApp
  GET other    → static files / SPA fallback
  otherwise    → servantApp
```

### 5. Name-Based Command Strings

REST handlers currently publish ID-based strings like
`"skill rename 1 broiler"`. Change to name-based:
`"skill rename grill broiler"`.

**Strategy**: Before publishing, look up the entity name from the repository.
These are admin-rate operations — the extra DB read is negligible.

Handlers that need name lookups:

| Handler | Currently has | Needs lookup |
|---------|-------------|--------------|
| handleDeleteSkill | skill ID | skill name |
| handleRenameSkill | skill ID + new name | old skill name |
| handleDeleteStation | station ID | station name |
| handleSetStationHours | station ID | station name |
| handleSetStationClosure | station ID | station name |
| handleAddImplication | two skill IDs | two skill names |
| handleRemoveImplication | two skill IDs | two skill names |
| handleGrantWorkerSkill | worker ID, skill ID | worker name, skill name |
| handleRevokeWorkerSkill | worker ID, skill ID | worker name, skill name |
| worker set-hours, etc. | worker ID | worker name |
| handleAddPin | worker ID, station ID | worker name, station name |
| handleRemovePin | worker ID, station ID | worker name, station name |

Handlers that already have names (no lookup needed):
`handleCreateSkill`, `handleCreateStation`, `handleCreateShift`,
`handleDeleteShift`, `handleSetConfig`, `handleApplyPreset`, etc.

**Lookup functions needed** (from existing Repository record):
- `repoGetSkill :: SkillId -> IO (Maybe Skill)` — check if this exists
- `repoGetStation` or similar — check availability
- Worker name lookup — likely via `repoGetUser` or worker info

### 6. Frontend: EventSource Integration

**Terminal.tsx changes**:

Add `"echo"` to the `OutputLine` type discriminator:

```typescript
interface OutputLine {
  type: "command" | "output" | "error" | "echo";
  text: string;
}
```

On mount (when authenticated), open an `EventSource`:

```typescript
const token = sessionStorage.getItem("token");
const es = new EventSource(`/api/events?token=${token}`);
es.onmessage = (event) => {
  const data = JSON.parse(event.data);
  setLines(prev => [...prev, { type: "echo", text: data.command }]);
};
```

Close the `EventSource` on unmount or session expiry.

**App.css changes**:

```css
.terminal-command { color: #ffffff; }  /* bright white for typed commands */
.terminal-echo    { color: #5390d9; }  /* light blue for echoed GUI events */
```

The prompt color stays `#5390d9`. Output text stays `#e0e0e0`.

### 7. Keepalive and Reconnection

- Server sends `:keepalive\n\n` (SSE comment) every 30 seconds
- `EventSource` auto-reconnects on disconnect (built into the browser API)
- On reconnect, the server creates a new subscription; events during the
  gap are lost (acceptable — these are UI echoes, not critical data)

## Dependencies

- No new Haskell packages needed — WAI streaming uses `Network.Wai` directly
  with `responseStream` from `wai`
- No new JS packages — `EventSource` is a browser built-in

## Risks

1. **Stdout capture lock**: The existing MVar in `ExecuteEnv` serializes
   stdout capture. SSE event delivery happens via bus callbacks, not stdout,
   so there is no interaction.

2. **Thread leak on disconnect**: Must ensure the bus subscription is
   cleaned up when the SSE connection drops. Use `bracket` pattern:
   subscribe on connect, unsubscribe in cleanup.

3. **Name lookup failures**: A handler might try to look up a name for an
   entity that was just deleted (e.g., `handleDeleteSkill` looks up the name,
   then deletes). Do the lookup before the mutation.

## Implementation Notes

Lessons learned during implementation — things the design didn't anticipate.

### WAI `responseStream` defers HTTP headers

WAI's `responseStream` does not send the HTTP status line or headers until
the first `write`+`flush` call.  For a normal response this is invisible,
but for SSE the browser's `EventSource` will sit in `CONNECTING` state
(never firing `onopen`) until data arrives.  The fix is to write an SSE
comment (`:ok\n\n`) and flush immediately when the streaming body starts.

### Bus callbacks run on the publisher's thread

`TopicBus.subscribe` invokes the callback synchronously on whatever thread
calls `publish`.  WAI's streaming `write`/`flush` functions are not safe to
call from arbitrary threads — they belong to the response callback's own
thread.  Calling them directly from a bus subscriber appeared to work in
unit tests but silently dropped data under real concurrency.  The fix is to
have the subscriber push `Builder` values onto a `Chan`, and have the
streaming thread's own loop read from the `Chan` and call `write`/`flush`.
