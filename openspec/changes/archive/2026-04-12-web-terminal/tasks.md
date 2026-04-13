## 1. Backend: /rpc/execute Endpoint

- [x] 1.1 Create `Server/Execute.hs` module with `executeCommandText :: Repository -> User -> String -> IO String` that parses a command string with `parseCommand`, builds a temporary `AppState` with default IORefs, calls `handleCommand` with stdout captured, and returns the output text
- [x] 1.2 Add `ExecuteReq` request type (`{"command": "..."}`) with FromJSON instance in `Server/Rpc.hs`
- [x] 1.3 Add `POST /rpc/execute` endpoint to the RPC API type returning `PlainText` content type
- [x] 1.4 Implement the execute handler: parse request, call `executeCommandText`, log to audit with `source='web'`, return text response
- [x] 1.5 Wire the execute endpoint into `rpcServer` and `fullServer`
- [x] 1.6 Add integration tests: successful command, unknown command, help, help group, auth required (401)

## 2. Backend: Static File Serving

- [x] 2.1 Add `wai-app-static` to `manars-kitchen.cabal` build-depends for the server executable
- [x] 2.2 Update `server-app/Main.hs` to compose the Servant app with a static file handler serving `web/dist/`, with SPA fallback to `index.html` for unmatched GET routes
- [x] 2.3 Verify API routes (`/api/*`, `/rpc/*`) take priority over static file serving

## 3. Frontend: Project Scaffolding

- [x] 3.1 Initialize Vite + React + TypeScript project in `web/` directory (`npm create vite@latest`)
- [x] 3.2 Configure `vite.config.ts` with proxy: `/api` and `/rpc` requests forward to `http://localhost:8080`
- [x] 3.3 Create `web/src/api/client.ts` — shared fetch wrapper that adds `Authorization: Bearer <token>` from sessionStorage, handles 401 by clearing token and redirecting to login
- [x] 3.4 Create `web/src/api/execute.ts` — `executeCommand(command: string): Promise<string>` function that POSTs to `/rpc/execute` and returns the text response

## 4. Frontend: Login Page

- [x] 4.1 Create `web/src/components/LoginPage.tsx` with username/password form and submit handler
- [x] 4.2 Implement login submission: POST to `/api/login`, store token and user info in sessionStorage on success, display error message on failure
- [x] 4.3 Implement logout: POST to `/api/logout`, clear sessionStorage, return to login page
- [x] 4.4 Wire routing in `web/src/App.tsx`: show LoginPage when no token in sessionStorage, show main app when authenticated

## 5. Frontend: Terminal Component

- [x] 5.1 Create `web/src/components/Terminal.tsx` with scrollable output area and command input field
- [x] 5.2 Implement command execution: on Enter, send command via `executeCommand()`, display `> command` and response in scrollback, clear input
- [x] 5.3 Implement command history: store commands in array, navigate with up/down arrow keys
- [x] 5.4 Implement auto-scroll: scroll to bottom of output area when new output is added
- [x] 5.5 Implement multi-line paste: detect pasted text with newlines, split into lines, execute each non-empty line sequentially
- [x] 5.6 Implement loading state: disable input and show indicator while a command is in flight
- [x] 5.7 Implement session expiry handling: on 401 from any API call, clear sessionStorage and redirect to login

## 6. Frontend: App Shell

- [x] 6.1 Create `web/src/components/AppShell.tsx` with header (app name, logged-in user, logout button) and terminal as main content
- [x] 6.2 Style the terminal with monospace font, dark background, appropriate padding and sizing to fill the viewport

## 7. Build and Integration

- [x] 7.1 Add `npm run build` step to produce `web/dist/` output
- [x] 7.2 Verify end-to-end: start `manars-server`, open browser, login, execute commands, see correct output
- [x] 7.3 Verify the CLI demo still works (`stack run manars-cli -- demo`)
- [x] 7.4 Run `stack clean && stack build && stack test` with zero warnings
