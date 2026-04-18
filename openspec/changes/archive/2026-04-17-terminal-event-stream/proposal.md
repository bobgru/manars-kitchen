# Terminal Event Stream

## Problem

The web terminal embedded in the UI cannot observe mutations made via GUI controls
(skill rename, implication toggles, station edits, etc.). When a user clicks in the
skills page, nothing appears in the terminal. The pub/sub bus delivers events
in-process but has no mechanism to push them to the browser.

## Solution

Add a Server-Sent Events (SSE) endpoint that streams command events from the
`AppBus` to the browser. The web terminal subscribes on login and displays
GUI-originated events as echoed commands in a distinct color (light blue vs
bright white for typed commands).

## Key Design Decisions

1. **SSE, not WebSocket** -- We only need server-to-client push. SSE is simpler,
   auto-reconnects, and works through proxies. Command input stays as HTTP POST.

2. **`GUI` source** -- Add `GUI` alongside `CLI | RPC | Demo` in `Source`. REST
   handlers publish as `GUI`; the terminal's `/rpc/execute` publishes as `RPC`.
   The SSE stream filters to `ceSource == GUI` so only click-originated events echo.

3. **CLI-equivalent commands with entity names** -- Echo strings use names instead
   of IDs: `skill rename grill broiler` rather than `skill rename 1 broiler`.
   Handlers look up names before publishing. These are admin-rate operations so
   the extra DB read is negligible.

4. **Same-session filtering** -- Each SSE connection is scoped to the authenticated
   session. Only events originating from the same session's GUI actions are echoed.
   This avoids cross-session noise (relevant once multiple users exist).

5. **SSE auth via query parameter** -- `EventSource` does not support custom
   headers, so the token is passed as a query parameter:
   `/api/events?token=abc123`.

   > **Security note**: Query parameters may appear in server logs, proxy logs,
   > and browser history. A safer alternative is a **ticket-based approach**:
   > POST to `/api/events/ticket` with the Bearer token to receive a short-lived
   > (e.g., 30-second), single-use ticket. Then open
   > `EventSource("/api/events?ticket=xyz")`. The server validates and consumes
   > the ticket on first use. This avoids long-lived tokens in URLs. For a
   > single-user local application this is not critical, but should be adopted
   > before any multi-user or public deployment.

## Scope

- Add `GUI` to the `Source` type
- Change REST handlers to publish as `GUI` with name-based command strings
- Add SSE endpoint with per-session bus subscription
- Update the web terminal React component to open an `EventSource`, display
  echoed commands in light blue
- Keep RPC handlers publishing as `RPC` (no change to terminal command flow)

## Out of Scope

- Cross-session event streaming (multi-user live collaboration)
- Streaming output for long-running commands (e.g., optimizer progress)
- Ticket-based SSE auth (noted as future hardening)
- xterm.js or full terminal emulation
