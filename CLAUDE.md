# Manar's Kitchen

## Build & test

- Always use `stack` to build, test, and run this project — never `cabal`. Use `stack build`, `stack test`, `stack exec`, etc.
- **Never pass `--fast`.** It changes the build flags, so nothing already compiled matches and stack rebuilds from scratch — which throws away the dependency build baked into the dev container image and any warm local cache. The same caution applies to any other flag that alters optimisation or GHC options ad hoc: pick the project's standard invocation rather than a one-off flag set. `--pedantic` is fine; it is what the pre-merge gate uses.
- Before considering a task complete, run `stack clean` then `stack build` and `stack test` to surface all warnings (incremental builds hide warnings that only appear after a clean). Fix every build and test warning before finishing.
- Always keep the demo working. After making changes, run the demo to confirm it still works end-to-end, and fix any breakage before reporting the task done.

## Workflow

- This project uses `grill-with-docs`, not OpenSpec. Grill the design first — numbered questions, one round at a time, a recommendation with each — and wait for answers before implementing. Capture what gets settled as glossary entries in `CONTEXT.md` and, when a decision is hard to reverse and the result of a real trade-off, an ADR in `docs/adr/`.
- Do not create new `openspec/changes/` entries. `openspec/specs/` and `openspec/changes/archive/` remain the historical record of what shipped — read them, don't extend them.
- `docs/STATUS.md` is the authoritative record of agreed next steps. Keep it current: when you finish an item, delete it rather than leaving a stale claim behind.
- Keep each shippable piece small and independent. Prefer breaking work into pieces that can be efficiently implemented over large monolithic changes; if a change feels large, look for natural split points.
