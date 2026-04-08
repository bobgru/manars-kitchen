## Context

The README is the primary documentation for the project. It currently covers the original CLI features but not the 6 features added in the `improve-interactive-cli-ux` change. This is a documentation-only change — no code modifications.

## Goals / Non-Goals

**Goals:**
- Document all 6 new CLI features so users can discover and use them
- Integrate new sections naturally into the existing README structure
- Update the project structure tree to reflect the new module

**Non-Goals:**
- Rewriting existing README sections that are still accurate
- Adding tutorial-style walkthroughs or screenshots
- Documenting internal implementation details of the new features

## Decisions

### 1. Insert new sections after "Interactive session", before "Workflow"

**Decision:** Add a new "CLI Features" section between the existing "Interactive session" and "Workflow" sections. This groups the UX features (help, naming, context, checkpoints) together and keeps the workflow section focused on the scheduling domain.

**Rationale:** The new features are cross-cutting CLI conveniences, not specific to any workflow step. Placing them in their own section avoids cluttering the step-by-step workflow with tangential information.

### 2. Update existing sections in-place where appropriate

**Decision:** Update the "Interactive session" example to show the two-level help, update the demo paragraph to mention auto-export, update import/export to mention demo-export.json, and add CLI/Resolve.hs to the project structure.

**Rationale:** Keeps the README consistent rather than having old sections contradict new features.

## Risks / Trade-offs

**[README length]** Adding 6 feature sections increases README length. -> Mitigation: Keep each section concise (3-8 lines + a code example). The README is already comprehensive; brief additions are consistent with the existing style.
