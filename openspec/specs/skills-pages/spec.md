# Spec: Skills Pages

## Overview

Two GUI pages for managing skills: a list page showing all skills with their implication chains, and a detail page for editing a skill's name and direct implications.

## Requirements

### R1: API client module

- Create `web/src/api/skills.ts` with functions:
  - `fetchSkills(): Promise<Array<{ id: number; name: string; description: string }>>` — GET /api/skills
  - `fetchImplications(): Promise<Record<number, number[]>>` — GET /api/skills/implications
  - `renameSkill(id: number, name: string): Promise<void>` — PUT /api/skills/:id
  - `addImplication(id: number, impliesId: number): Promise<void>` — POST /api/skills/:id/implications
  - `removeImplication(id: number, impliesId: number): Promise<void>` — DELETE /api/skills/:id/implications/:impliedId
- All functions use the existing `apiFetch` wrapper (handles auth tokens and 401 detection).

### R2: Skills list page

- Route: `/skills`
- Fetches skills and implications on mount.
- Displays a table with columns:
  - **Name** — the skill name, links to the detail page
  - **Implies** — direct implications shown as skill names; transitively implied skills shown in parentheses
- Example rendering:
  ```
  Name        │ Implies
  ────────────┼──────────────────────
  Grill       │ Prep
  Management  │ Grill (Prep)
  Prep        │
  Cleaning    │
  ```
- Empty state: "No skills defined" message if there are no skills.

### R3: Transitive closure computation

- The frontend computes the transitive closure from the direct implications map.
- For display, direct implications are listed by name. Transitively implied skills (those reachable but not directly implied) are appended in parentheses.
- Example: if Management directly implies Grill, and Grill directly implies Prep, then Management's "Implies" column shows "Grill (Prep)" — Grill is direct, Prep is transitive.

### R4: Skill detail page

- Route: `/skills/:id`
- Fetches the skill (by ID from the skills list) and implications on mount.
- Shows a "Back to Skills" link at the top.
- **Name field**: a text input pre-filled with the current name, plus a Save button. Save calls `renameSkill` and shows brief confirmation.
- **Implies checkboxes**: one checkbox per other skill (excluding self). Checked means "this skill directly implies that skill." Toggling a checkbox immediately fires `addImplication` or `removeImplication`, then refetches implications to update the transitive closure display.
- **Transitive closure display**: a read-only line below the checkboxes showing the full effective skill set, e.g. "Effective skills: Grill, Prep". Updated after each checkbox toggle. If empty, shows "None".
- 404 handling: if the skill ID doesn't match any skill, show a "Skill not found" message with a link back to the list.

### R5: Loading and error states

- Show a loading indicator while fetching skills or implications.
- Show an error message if a fetch or mutation fails (network error, server error).
- Disable checkboxes and the save button while a mutation is in flight to prevent double-submits.

## Files to create

| File | Purpose |
|------|---------|
| `web/src/api/skills.ts` | REST client for skills endpoints |
| `web/src/components/SkillsListPage.tsx` | Skills list with implication chains |
| `web/src/components/SkillDetailPage.tsx` | Skill name edit + implication checkboxes |

## Files to modify

| File | Changes |
|------|---------|
| `web/src/App.css` | Table styles, form styles, checkbox styles, detail page layout |
