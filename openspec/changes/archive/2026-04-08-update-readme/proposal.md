## Why

The README documents the CLI's command interface but does not mention 6 features recently added in the `improve-interactive-cli-ux` change: two-level help, name-based entity resolution, session context with dot-substitution, compact schedule display, checkpoint/rollback, and demo auto-export. Users reading the README won't know these features exist. The project structure section also needs updating to reflect the new `CLI/Resolve.hs` module.

## What Changes

- **New section: Name-based entity references** — Document that commands accept entity names (e.g., `worker grant-skill marco grill`) in addition to numeric IDs. Explain case-insensitivity and numeric-preferred behavior.
- **New section: Session context** — Document `use <type> <name>`, `context view`, `context clear`, and the `.` placeholder.
- **New section: Compact schedule view** — Document `schedule view-compact <name>`.
- **New section: Checkpoints** — Document `checkpoint create/commit/rollback/list` for safe experimentation.
- **Updated: Interactive session example** — Show `help` producing group summary and `help <group>` for details, replacing the old monolithic help reference.
- **Updated: Demo section** — Note that demo mode now exports `demo-export.json` on completion.
- **Updated: Project structure** — Add `CLI/Resolve.hs` to the file tree.
- **Updated: Import/export section** — Mention that demo export is importable.

## Capabilities

### New Capabilities
- `readme-cli-features`: Documentation of the 6 new CLI UX features in the README

### Modified Capabilities

## Impact

- **README.md** — Only file modified. No code, API, or dependency changes.
