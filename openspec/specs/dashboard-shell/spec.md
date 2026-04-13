# Spec: Dashboard Shell

## Overview

Introduce the admin dashboard layout: a sidebar for navigation, a main content area driven by React Router, and a persistent terminal pane at the bottom. This is the skeleton that all future entity pages will slot into.

## Requirements

### R1: React Router integration

- Add `react-router` (v7) as a dependency.
- Wrap the authenticated app in a `BrowserRouter`.
- Define routes:
  - `/` — DashboardPage (placeholder)
  - `/skills` — SkillsListPage
  - `/skills/:id` — SkillDetailPage
- Unknown routes redirect to `/`.

### R2: Sidebar navigation

- A vertical sidebar on the left side of the layout.
- Contains navigation links: Dashboard, Skills, Stations (placeholder), Workers (placeholder), Shifts (placeholder), Schedules (placeholder), Calendar (placeholder).
- The active link is visually highlighted.
- Placeholder links navigate to the dashboard (or show a "coming soon" message). They should not be dead links.

### R3: Layout structure

- The layout is a CSS grid or flexbox with three regions:
  - Header (full width, top)
  - Sidebar (left column, below header)
  - Content area (right of sidebar, split vertically into Outlet + Terminal)
- The content area splits vertically: the route Outlet takes the top portion, the Terminal takes the bottom portion.
- The terminal pane has a visible border/divider separating it from the route content.
- The overall layout fills the viewport (100vh). Both the route content and terminal are independently scrollable.

### R4: Terminal persistence

- The Terminal component is rendered outside the React Router `<Outlet />`.
- Navigating between pages does NOT unmount or remount the Terminal.
- Terminal history, input state, and scroll position are preserved across navigation.

### R5: Terminal pane sizing

- The terminal pane occupies roughly the bottom third of the content area by default.
- A reasonable fixed split is acceptable for now (no drag-to-resize required).

### R6: Existing functionality preserved

- The login page is unchanged.
- Logout still works.
- Session expiry detection still works.
- The terminal REPL functions identically to today.

## Files to create

| File | Purpose |
|------|---------|
| `web/src/components/Sidebar.tsx` | Navigation sidebar with route links |
| `web/src/components/DashboardPage.tsx` | Placeholder landing page |

## Files to modify

| File | Changes |
|------|---------|
| `web/package.json` | Add `react-router` dependency |
| `web/src/App.tsx` | Add BrowserRouter, route definitions, pass routes to AppShell |
| `web/src/components/AppShell.tsx` | Restructure layout: sidebar + content (outlet + terminal) |
| `web/src/App.css` | Sidebar styles, split layout, content area grid |
