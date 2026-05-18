# Changelog for `manars-kitchen`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

### Changed (BREAKING)

- `worker deactivate <name>` now follows a safe-then-force protocol mirroring `worker delete` / `worker force-delete`. It commits the deactivation only when the worker has zero pinned assignments, zero open-draft entries, and zero future calendar entries. If any are nonzero, it prints the impact counts and refuses to commit.
- `PUT /api/workers/:name/deactivate` now returns `204 No Content` on a zero-impact commit and `409 Conflict` (with `{pinsRemoved, draftsRemoved, calendarRemoved}` body) when impact is nonzero. State is unchanged on 409.
- Scripts that relied on the old commit-unconditionally behavior should switch to `worker force-deactivate <name>` (CLI) or `PUT /api/workers/:name/deactivate/force` (REST).

### Added

- `worker force-deactivate <name>` CLI verb: unconditionally commits deactivation and reports counts (mirrors `worker force-delete`).
- `PUT /api/workers/:name/deactivate/force` endpoint: returns `200 OK` with `{pinsRemoved, draftsRemoved, calendarRemoved}` after committing.
- `GET /api/workers?status=active|inactive|all` endpoint returning a slim `[WorkerSummaryResp]` for the workers admin UI.
- React admin pages: `/workers` list (status filter, create buttons, per-row actions, deactivate-with-preview, delete-with-preview, dual SSE subscription) and `/workers/:name` detail (rename, status toggle, read-only placeholder cards for the deferred sections).

## 0.1.0.0 - YYYY-MM-DD
