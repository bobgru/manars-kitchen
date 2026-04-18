## 1. GUI Source Type

- [x] 1.1 Add `GUI` to `data Source = CLI | RPC | GUI | Demo` in `src/Service/PubSub.hs`; add `sourceString GUI = "gui"`; update `deriving` if needed
- [x] 1.2 Change `logRest` in `server/Server/Handlers.hs` to publish with `GUI` instead of `RPC`

## 2. Name-Based Command Strings

- [x] 2.1 Add repository lookup helpers needed by REST handlers: verify `repoGetSkill`, `repoGetStation`, and worker-name lookup functions exist or add them
- [x] 2.2 Update REST handlers that currently publish ID-based command strings to look up entity names before publishing; do lookups before mutations (see design.md handler table for full list)

## 3. SSE Endpoint

- [x] 3.1 Create `server/Server/EventStream.hs` with `eventStreamApp :: Repository -> AppBus -> Application`; implement token auth from query string using the same validation chain as `authHandler`
- [x] 3.2 Implement SSE streaming: subscribe to `busCommands` with `".*"` pattern, filter to `ceSource == GUI` and matching `ceUsername`, write SSE-formatted JSON (`data: {...}\n\n`) to response body
- [x] 3.3 Add 30-second keepalive (`:keepalive\n\n` SSE comment) using a concurrent timer
- [x] 3.4 Implement clean disconnection with bracket pattern: subscribe on connect, unsubscribe in cleanup
- [x] 3.5 Wire `eventStreamApp` into `spaFallback` in `server-app/Main.hs`: intercept `GET /api/events` before Servant routing; pass `repo` and `eeBus execEnv`

## 4. Frontend EventSource Integration

- [x] 4.1 Add `"echo"` to the `OutputLine` type discriminator in `web/src/components/Terminal.tsx`
- [x] 4.2 Open `EventSource("/api/events?token=...")` on mount when authenticated; parse incoming JSON and append echo lines to scrollback; close on unmount
- [x] 4.3 Update `web/src/App.css`: change `.terminal-command` color to `#ffffff` (bright white for typed commands); add `.terminal-echo` class with color `#5390d9` (light blue for echoed events)
- [x] 4.4 Render echo lines with `[echo]` prefix and `.terminal-echo` CSS class in the terminal scrollback

## 5. Tests

- [x] 5.1 Add `sourceString GUI` test in `test/PubSubSpec.hs`
- [x] 5.2 Integration test: REST handler publishes CommandEvent with `ceSource == GUI` and correct username
- [x] 5.3 Integration test: SSE endpoint returns 401 for missing/invalid token
- [x] 5.4 Integration test: SSE endpoint streams GUI events to authenticated client
- [x] 5.5 Verify all existing tests pass (`stack test`)

## 6. Cleanup

- [x] 6.1 Run `stack clean && stack build` and fix all warnings
- [x] 6.2 Verify the demo still works
