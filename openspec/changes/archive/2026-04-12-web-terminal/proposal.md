## Why

The entire application is accessible only through the CLI. Adding a browser-based terminal unlocks web access to every command without building per-feature GUI controls. This is the fastest path to "whole app in the browser" and establishes the frontend project scaffolding (Vite + React + TypeScript) that all future GUI work builds on.

## What Changes

- Add a `POST /rpc/execute` endpoint that accepts a raw command string, parses it with the existing CLI parser, executes it, and returns pre-formatted text. This avoids duplicating command parsing in TypeScript.
- Configure Warp to serve static files from `web/dist/` at `/`, enabling single-process deployment (API + frontend from one binary).
- Create a new `web/` directory with a Vite + React + TypeScript project.
- Implement a browser login page that authenticates via `POST /api/login` and stores the session token in `sessionStorage` (one session per browser tab).
- Implement a browser terminal component with command input, scrollable output history, and up/down arrow command history.

## Capabilities

### New Capabilities
- `rpc-execute`: Server-side command execution endpoint — accepts a raw command string, parses, executes, and returns formatted text output.
- `static-file-serving`: Warp serves the built frontend assets at `/`, coexisting with `/api/` and `/rpc/` routes.
- `web-login`: Browser login page — username/password form, token stored in sessionStorage, logout support.
- `web-terminal`: Browser-based terminal — command input, scrollback display, command history, communicates via `/rpc/execute`.

### Modified Capabilities
- `rest-api-server`: Server startup now also mounts static file serving for the frontend.

## Impact

- **New dependency**: The `web/` directory introduces Node.js tooling (npm, Vite, React, TypeScript) as a build-time dependency for the frontend. The Haskell build is unaffected.
- **Server module changes**: `Server.Api` gains the `/rpc/execute` endpoint and static file middleware. `server-app/Main.hs` gains a static file serving path configuration.
- **New Haskell module**: A command execution module that bridges the CLI parser and text formatters to an HTTP handler.
- **CORS**: The Vite dev server proxies API calls during development; production serves everything from one origin, so no CORS configuration is needed in production.
