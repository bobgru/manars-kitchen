# Manar's Kitchen

## Build & test

- Always use `stack` to build, test, and run this project — never `cabal`. Use `stack build`, `stack test`, `stack exec`, etc.
- Before considering a task complete, run `stack clean` then `stack build` and `stack test` to surface all warnings (incremental builds hide warnings that only appear after a clean). Fix every build and test warning before finishing.
- Always keep the demo working. After making changes, run the demo to confirm it still works end-to-end, and fix any breakage before reporting the task done.

## Workflow

- Keep OpenSpec changes small and independently shippable. Prefer breaking work into pieces that can be efficiently implemented over large monolithic changes; if a change feels large, look for natural split points.
