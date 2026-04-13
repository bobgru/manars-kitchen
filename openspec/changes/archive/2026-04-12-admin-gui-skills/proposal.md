# Proposal: Admin GUI — Skills

## Problem

The web interface is currently a terminal emulator only. There is no graphical UI for browsing or editing entities. The terminal provides full power but no visual context — you can't glance at the skill list, see implication chains, or edit relationships without remembering command syntax.

## Solution

Add a browser-based admin dashboard with skills as the first entity page. The dashboard introduces the shell (routing, sidebar navigation, layout) that all future entity pages will reuse. The terminal remains as a full interactive REPL in a bottom pane, coexisting with the GUI.

### Backend additions

Four new REST endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| `PUT` | `/api/skills/:id` | Rename a skill |
| `GET` | `/api/skills/implications` | Read all direct implications |
| `POST` | `/api/skills/:id/implications` | Add an implication |
| `DELETE` | `/api/skills/:id/implications/:impliedId` | Remove an implication |

The rename endpoint is a new capability (no CLI equivalent exists yet). It establishes a pattern that will apply to other entities as they get GUI pages.

### Frontend — dashboard shell

- **React Router** for client-side page navigation
- **Sidebar** with entity categories (Skills active; Stations, Workers, Shifts, Schedules, Calendar as placeholders)
- **Terminal pane** at bottom of the main content area — the existing Terminal component, fully interactive
- **Lightweight CSS framework** (classless/semantic, e.g. Pico CSS) for baseline styling — chosen to be easy to replace when requirements get more ambitious

### Frontend — skills list page

A table showing all skills with their implication chains:

```
  Name       │ Implies
  ───────────┼────────────────────────
  Grill      │ Prep
  Management │ Grill (Prep)
  Prep       │ (none)
  Cleaning   │ (none)
```

Direct implications are shown by name. Transitively implied skills appear in parentheses. Each row links to the detail page.

### Frontend — skill detail page

- **Editable name field** with Save button
- **Checkboxes** for direct implications — one per other skill, checked means "this skill implies that one"
- **Transitive closure** shown as a read-only line below the checkboxes (e.g. "Effective skills: Grill, Prep")
- **Back link** to the list page
- Mutations fire immediately via REST

### Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  Manar's Kitchen                         admin    [Logout]      │
├──────────┬──────────────────────────────────────────────────────┤
│          │                                                       │
│ Dashboard│  [Entity page content]                                │
│ Skills ◄ │                                                       │
│ Stations │                                                       │
│ Workers  │                                                       │
│ Shifts   │                                                       │
│ Schedules│                                                       │
│ Calendar │                                                       │
│          │                                                       │
│          ├──────────────────────────────────────────────────────┤
│          │  Terminal (full REPL)                                  │
│          │  manars> _                                            │
└──────────┴──────────────────────────────────────────────────────┘
```

## Not in scope

- **Graph visualization** of the implication DAG (planned for a follow-up)
- **Draft/commit model** per GUI context (planned — will add discard/commit buttons and unsaved-changes alerts)
- **Other entity pages** (stations, workers, shifts, etc.) — the shell supports them but content is deferred
- **Skill description editing** — included in the data model but not surfaced in the detail page yet
- **Demo theater** — scripted GUI replay with floating terminal (separate initiative)

## Risks

- **CSS framework choice**: a classless framework keeps things simple now but may not scale to more complex layouts. Chosen deliberately for easy replacement.
- **Two input paths**: both the GUI and terminal can mutate state. The GUI fires REST calls; the terminal fires RPC commands. Both go through the same service layer and audit log, so they stay consistent. But the GUI won't auto-refresh when the terminal makes a change (and vice versa). For now this is acceptable — a future pub/sub integration can solve it.
