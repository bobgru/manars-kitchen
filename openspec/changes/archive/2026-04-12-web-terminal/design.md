## Context

The application is fully functional through the CLI and has a complete REST/RPC backend with authentication. The CLI's `handleCommand` function in `CLI/App.hs` is a ~1700-line pattern match that calls service-layer functions and prints formatted text to stdout. The RPC layer in `Server/Rpc.hs` provides 47 typed JSON endpoints. The goal is to get the entire app working in a browser with minimal new code by reusing the existing CLI command parser and text formatters.

## Goals / Non-Goals

**Goals:**
- Browser-based login and terminal that exercises every existing command
- Single-process deployment (Warp serves API + static files)
- Establish the `web/` project with Vite + React + TypeScript for all future frontend work
- Identical terminal output to the CLI — same parser, same formatters

**Non-Goals:**
- GUI controls, menus, or rich calendar views (future changes)
- Client-side command parsing (the typed `/rpc/*` endpoints remain for future GUI use)
- Stateful session commands (`context`, ephemeral unfreezes) — terminal is stateless initially
- Tab completion, syntax highlighting, or other advanced terminal features
- Mobile-responsive layout (the terminal is a desktop experience; mobile comes with the Worker UI)

## Decisions

### 1. Capture stdout from existing `handleCommand` for text output

**Decision**: The `/rpc/execute` endpoint will create a temporary `AppState`, call the existing `handleCommand` function, and capture its stdout output as a `String` to return in the HTTP response.

**Alternatives considered**:
- *New parallel dispatch function*: A `executeCommandText :: Command -> IO String` that reimplements the formatting logic. Avoids stdout capture but duplicates the ~1700-line handleCommand and creates a sync problem.
- *Refactor handleCommand to return String*: Clean but touches every branch of a massive function — high risk for a foundational change.

**Rationale**: Capturing stdout is pragmatic for v1. It reuses 100% of existing formatting logic with zero duplication. The `handleCommand` function already works correctly; we just redirect where its output goes. If this proves limiting, we can refactor `handleCommand` to return text later. The temporary `AppState` will use empty/default IORefs since we're stateless — commands that depend on session state (context, unfreezes) will produce their "no context set" default behavior.

### 2. Static files served by Warp via wai-app-static

**Decision**: Use `wai-app-static` (or `servant-raw` with a static file handler) to serve `web/dist/` at `/`. API routes (`/api/*`, `/rpc/*`) take priority; unmatched routes fall through to the static file handler, which serves `index.html` for client-side routing.

**Rationale**: Single-process deployment avoids ops complexity. The static file handler is a WAI middleware, so it composes naturally with the existing Servant app. In development, Vite serves the frontend directly and proxies API calls to Warp, so this path is only used in production builds.

### 3. Vite + React + TypeScript in `web/` directory

**Decision**: The frontend lives in `web/` as a standard Vite React-TS project. It is completely independent of the Haskell build — `stack build` does not touch `web/`, and `npm run build` does not touch Haskell.

**Rationale**: Clean separation. The Haskell developer can ignore `web/` when working on the backend, and vice versa. Vite provides fast dev-server hot reload and optimized production builds.

### 4. sessionStorage for token, one session per tab

**Decision**: On login, the token is stored in `sessionStorage`. Every API call includes it as `Authorization: Bearer <token>`. Closing the tab loses the token (and the session idles out on the server).

**Alternatives considered**:
- *localStorage*: Persists across tabs and browser restarts — doesn't match the per-tab session model.
- *In-memory only*: Lost on page refresh, which is too disruptive.

**Rationale**: `sessionStorage` is per-tab by browser specification, exactly matching the desired "one session per browser tab" model. Survives refresh within the tab, gone when the tab closes.

### 5. Vite dev proxy for API calls

**Decision**: `vite.config.ts` configures a proxy: requests to `/api/*` and `/rpc/*` forward to `http://localhost:8080`. In development, the user runs two terminals — `stack run manars-server` and `cd web && npm run dev`.

**Rationale**: Standard Vite development pattern. No CORS configuration needed in development or production. The proxy is only used during development; in production, everything is served from one origin.

### 6. Help command works through `/rpc/execute`

**Decision**: The `help` command is just another command string sent to `/rpc/execute`. The server's existing help text system handles it. No separate help endpoint needed.

**Rationale**: The CLI's `handleCommand` already handles `Help`, `HelpGroup`, and `HelpCommand` variants. Since `/rpc/execute` reuses `handleCommand`, help works automatically.

## Risks / Trade-offs

**[stdout capture is fragile]** → Capturing stdout works for synchronous commands but could be problematic for commands that use concurrent output (e.g., optimizer progress). Mitigation: progress output is routed through the pub/sub system, not stdout. The optimizer callback is wired separately. For v1, no progress reporting in the browser terminal — just the final result.

**[Stateless terminal limits some workflows]** → Commands like `context worker 3` and `what-if` sessions that depend on `AppState` IORefs won't work as expected. Mitigation: These are documented as out of scope. The terminal is still useful for the vast majority of commands. Stateful support comes later with server-side AppState per session.

**[Two build systems]** → Developers need both `stack` and `npm` toolchains. Mitigation: The two are fully independent. A backend-only developer never needs to run `npm`. The frontend build is only needed for production deployment.

**[wai-app-static dependency]** → Adds a new Haskell dependency for static file serving. Mitigation: `wai-app-static` is a mature, well-maintained package in the WAI ecosystem. Alternatively, `servant-raw` with a custom handler could avoid the dependency, using only WAI's built-in file serving.
