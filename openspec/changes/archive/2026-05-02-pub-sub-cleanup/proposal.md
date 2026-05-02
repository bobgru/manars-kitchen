# Pub/Sub Cleanup

## Summary

Follow-up from the topic-routed-pub-sub change. Three tasks were deferred because they depend on migrating test helpers to use the bus before the old logging functions can be removed.

## Tasks

1. **Remove `repoLogCommand` and `repoLogRpcCommand` from `Repository`**: These were kept because test helpers still call them directly. Migrate test helpers to publish through the bus, then remove the old functions from the Repository record and SQLite implementation.

2. **Fix demo script hardcoded IDs**: Draft commands in the demo script use hardcoded IDs that don't match auto-increment sequences. Capture IDs from `draft create` output instead. (Pre-existing issue, not introduced by topic-routed-pub-sub.)

3. **Remove `repoLogCommand` and `repoLogRpcCommand` once test helpers are migrated**: Final cleanup after task 1 is complete -- remove dead code from Repo/SQLite.hs and any remaining references.

## Context

These were tasks 10.1, 11.1, and 11.2 in the topic-routed-pub-sub change, marked as deferred/follow-up.
