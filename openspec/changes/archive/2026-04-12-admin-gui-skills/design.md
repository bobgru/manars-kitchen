# Design: Admin GUI — Skills

## Architecture

The change adds a GUI layer alongside the existing terminal. Both coexist in a split layout and share the same backend.

```
┌─────────────────────────────────────────────────────────────────┐
│  Header (title, username, logout)                                │
├──────────┬──────────────────────────────────────────────────────┤
│          │  ┌────────────────────────────────────────────────┐  │
│ Sidebar  │  │  Route content (Outlet)                        │  │
│          │  │  - DashboardPage        /                      │  │
│ nav links│  │  - SkillsListPage       /skills                │  │
│          │  │  - SkillDetailPage      /skills/:id            │  │
│          │  └────────────────────────────────────────────────┘  │
│          │  ┌────────────────────────────────────────────────┐  │
│          │  │  Terminal (persistent, full REPL)               │  │
│          │  └────────────────────────────────────────────────┘  │
└──────────┴──────────────────────────────────────────────────────┘
```

### Component tree

```
App
├── LoginPage (when unauthenticated)
└── BrowserRouter (when authenticated)
    └── AppShell
        ├── Header
        ├── Sidebar
        ├── <Outlet />        ← React Router renders page here
        └── Terminal           ← outside Outlet, persists across navigation
```

The Terminal is rendered outside the router Outlet so it does not unmount/remount when the user navigates between pages. History and scroll position are preserved.

## Key decisions

### Extend custom CSS rather than adding a framework

The existing frontend has a coherent dark theme (blues/grays) with custom CSS. For this scope — one table, one form, checkboxes — extending the existing styles is simpler than introducing a CSS framework that would fight the current theme. If we need a framework later when the UI gets more complex, the custom CSS is straightforward to migrate away from.

### Implications: flat edge list from backend, closure computed on frontend

`GET /api/skills/implications` returns direct implication edges as a JSON object:

```json
{ "1": [2], "3": [1] }
```

Keys are skill IDs; values are arrays of implied skill IDs. The frontend computes the transitive closure for display. With a handful of skills this is trivial (fixed-point iteration over the map), and it avoids a second endpoint or a more complex response shape. When a checkbox is toggled, the frontend fires a POST or DELETE, then refetches the implications to recompute.

### Skill rename: new repo + service + REST capability

No rename operation exists in the codebase today. The change adds:

- `repoRenameSkill :: SkillId -> String -> IO ()` in the repository interface
- `sqlRenameSkill` in SQLite (UPDATE skills SET name = ? WHERE id = ?)
- `renameSkill` in Service.Worker
- `PUT /api/skills/:id` REST endpoint with `{ "name": "..." }` body

This establishes a rename pattern for other entities later.

### Implications: targeted add/remove rather than bulk save

The service layer already has `addSkillImplication`. We add a corresponding `removeSkillImplication`. The REST endpoints map to these:

- `POST /api/skills/:id/implications` with `{ "impliesSkillId": N }` — add edge
- `DELETE /api/skills/:id/implications/:impliedId` — remove edge

This is more RESTful than a bulk "replace all implications" approach and generates clearer audit log entries.

### GUI mutations are immediate

Checkbox toggles and name saves fire REST calls immediately. There is no client-side draft/commit model yet (noted as a future enhancement in the proposal). The terminal reflects mutations through the audit log.

### No auto-refresh across input paths

If the user types `skill implication 1 2` in the terminal, the GUI skills page will not auto-update. The user must navigate away and back (or refresh) to see the change. This is acceptable for now. The internal pub/sub system exists in the backend and could power auto-refresh later via SSE.

## Backend changes

### Repository interface (Repo/Types.hs)

Add to the Repository record:

```haskell
, repoRenameSkill :: SkillId -> String -> IO ()
, repoListSkillImplications :: IO [(SkillId, SkillId)]
, repoRemoveSkillImplication :: SkillId -> SkillId -> IO ()
```

### SQLite implementation (Repo/SQLite.hs)

```sql
-- rename
UPDATE skills SET name = ? WHERE id = ?

-- list implications (already queried in loadSkillCtx, but we need a standalone query)
SELECT skill_id, implies_skill_id FROM skill_implications

-- remove implication
DELETE FROM skill_implications WHERE skill_id = ? AND implies_skill_id = ?
```

### Service layer (Service/Worker.hs)

- `renameSkill :: Repository -> SkillId -> String -> IO ()`
- `removeSkillImplication :: Repository -> SkillId -> SkillId -> IO ()`
- `listSkillImplications :: Repository -> IO (Map SkillId [SkillId])`

### REST endpoints (Server/Api.hs, Server/Handlers.hs)

| Method | Path | Body | Response |
|--------|------|------|----------|
| `PUT` | `/api/skills/:id` | `{ "name": "..." }` | 204 |
| `GET` | `/api/skills/implications` | — | `{ "1": [2], ... }` |
| `POST` | `/api/skills/:id/implications` | `{ "impliesSkillId": N }` | 204 |
| `DELETE` | `/api/skills/:id/implications/:impliedId` | — | 204 |

All mutation endpoints require admin auth.

## Frontend changes

### New dependencies

- `react-router` (v7) for client-side routing

### New files

| File | Purpose |
|------|---------|
| `api/skills.ts` | REST client functions for skills + implications |
| `components/Sidebar.tsx` | Navigation sidebar |
| `components/DashboardPage.tsx` | Placeholder landing page |
| `components/SkillsListPage.tsx` | Skills table with implication chains |
| `components/SkillDetailPage.tsx` | Edit name + implication checkboxes |

### Modified files

| File | Change |
|------|--------|
| `App.tsx` | Add BrowserRouter, route definitions |
| `AppShell.tsx` | Add Sidebar, split layout (sidebar / content+terminal) |
| `App.css` | Sidebar styles, content area layout, table/form styles |

### Transitive closure algorithm (frontend)

```typescript
function transitiveClosure(
  direct: Record<number, number[]>
): Record<number, number[]> {
  const result: Record<number, Set<number>> = {};
  for (const [id, implied] of Object.entries(direct)) {
    result[Number(id)] = new Set(implied);
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const [id, skills] of Object.entries(result)) {
      for (const sk of [...skills]) {
        const transitive = result[sk];
        if (transitive) {
          for (const t of transitive) {
            if (!result[Number(id)].has(t)) {
              result[Number(id)].add(t);
              changed = true;
            }
          }
        }
      }
    }
  }
  // Convert back to arrays
  const out: Record<number, number[]> = {};
  for (const [id, skills] of Object.entries(result)) {
    out[Number(id)] = [...skills];
  }
  return out;
}
```
