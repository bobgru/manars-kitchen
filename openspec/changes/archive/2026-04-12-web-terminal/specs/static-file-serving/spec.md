## ADDED Requirements

### Requirement: Serve frontend static files
The server SHALL serve static files from a configurable directory (defaulting to `web/dist/`) for all URL paths that do not match `/api/*` or `/rpc/*` routes.

#### Scenario: Serve index.html at root
- **WHEN** a GET request is made to `/`
- **THEN** the server returns the contents of `web/dist/index.html` with `Content-Type: text/html`

#### Scenario: Serve JS bundle
- **WHEN** a GET request is made to `/assets/index-abc123.js`
- **THEN** the server returns the corresponding file from `web/dist/assets/` with `Content-Type: application/javascript`

#### Scenario: Client-side routing fallback
- **WHEN** a GET request is made to a path like `/terminal` that does not match a static file or an API route
- **THEN** the server returns `web/dist/index.html` (SPA fallback) so the React router can handle the path

### Requirement: API routes take priority over static files
The server SHALL match `/api/*` and `/rpc/*` routes before falling through to static file serving. An API request SHALL never be served a static file.

#### Scenario: API route is not shadowed
- **WHEN** a POST is made to `/api/login`
- **THEN** the request is handled by the login API handler, not the static file server
