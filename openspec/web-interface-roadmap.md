# Web Interface Roadmap

This document captures the vision and sequencing for evolving Manars Kitchen from a CLI application to a web-accessible system. Individual changes reference this roadmap for context but are scoped independently.

## Vision

Two audiences interact with the system through a browser:

- **Admin**: Configuration, schedule generation, what-if exploration, draft management, calendar views. The admin UI includes a terminal pane that renders the audit log as command strings, providing a CLI-like experience alongside GUI controls for discoverability.
- **Workers**: View their schedule slice, submit absence/vacation requests. Mobile-friendly responsive web (not a native app). Workers log in but their operations are stateless -- no server-side session needed.

The CLI remains a first-class client. The backend serves all three interfaces (CLI, admin browser, worker browser) through the same service layer.

## Architecture

```
  CLI ──────────► RPC layer ──────► REST API
                  (translates         │
                   commands to        │
                   REST calls)        │
                                      │
  Admin UI ────► REST API ◄───────────┘
  (GUI + terminal pane)               │
                                      │
  Worker UI ───► REST API (subset) ◄──┘
                                      │
                              ┌───────┴───────┐
                              │ Service Layer  │
                              │ (sessions,     │
                              │  pub/sub)      │
                              ├───────────────┤
                              │ Domain (pure)  │
                              ├───────────────┤
                              │ Repo (SQLite)  │
                              └───────────────┘
```

## Key Design Decisions

**Structured audit log.** The audit log stores structured metadata (entity type, operation, IDs, date ranges) as the canonical record. Command strings are a rendering -- generated from metadata for terminal pane display. All three interfaces (CLI, RPC, REST) log the same structured records.

**CommandClassifier module.** A shared module provides `classify` (command string to metadata) and `render` (metadata to command string). Used by audit logging, terminal pane display, and hint session rebase.

**Server-side sessions.** Session state (context, hints, checkpoints, unfreezes) moves from CLI IORef fields to a database-backed session record. The CLI becomes a client that holds a session ID. This enables crash recovery and multi-client access.

**Persistent hint sessions with rebase.** Hint sessions persist as a JSON blob of `[Hint]` plus an audit log checkpoint. On resume, new audit entries are classified as irrelevant/compatible/conflicting/structural. Compatible changes auto-integrate; conflicts present an interactive rebase UI. Sessions are resumable across days and tied to drafts.

**RPC implemented over REST.** CLI commands map 1:1 to RPC endpoints. Each RPC endpoint is implemented as a sequence of REST calls. The REST API is the real contract; RPC is a convenience translation.

**Internal pub/sub.** A lightweight publish/subscribe mechanism in the service layer enables progress feedback for long-running operations (schedule generation, hint session rebase, audit replay). Consumers include SSE streaming to the browser, CLI status output, or nothing (events dropped if unsubscribed).

**Auth on every endpoint.** All HTTP endpoints require authentication and authorization. Role-based access distinguishes admin operations from worker operations.

## Change Sequence

```
  1. Structured audit log ──────────────────────────┐
                                                     ├──► 3. Persistent hint sessions
  2. Server-side sessions ──────────────────────────┘       (with rebase)
                                │
  2a. Internal pub/sub          │
                                │
                                ├──► 4. REST API
                                │       │
                                │       ├──► 5. RPC-over-REST
                                │       │       │
                                │       │       └──► 6. Demo HTTP client
                                │       │
                                │       ├──► 7. Auth + role-based access
                                │       │       │
                                │       │       ├──► 8. Admin UI
                                │       │       │
                                │       │       └──► 9. Worker UI (mobile-friendly)
```

Changes 1 and 2 are independent, backend-only, and testable via the existing CLI. Change 3 requires both. The HTTP and browser layers fan out from there. Change 2a (pub/sub) is a small utility that can slot in anywhere before the HTTP layer.
