## 1. TopicBus Module

- [x] 1.1 Rename `PubSub e` to `TopicBus e` in `src/Service/PubSub.hs`; add `Topic` newtype; change `subscribe` to accept a regex pattern `String` and `(Topic -> e -> IO ())` callback; change `publish` to accept a `Topic` and match against compiled regexes; update exports
- [x] 1.2 Add `AppBus` record with `busCommands :: TopicBus CommandEvent` and `busProgress :: TopicBus ProgressEvent`; add `newAppBus :: IO AppBus`
- [x] 1.3 Add `buildTopic :: CommandMeta -> Topic` function
- [x] 1.4 Update `manars-kitchen.cabal` if new modules or dependencies are needed (e.g., `regex-posix` or `regex-tdfa`)

## 2. CommandEvent Type and Publishing

- [x] 2.1 Define `Source` (`CLI | RPC`) and `CommandEvent` types (in `Service.PubSub` or a new module)
- [x] 2.2 Add `publishCommand :: TopicBus CommandEvent -> Source -> String -> String -> IO ()` helper
- [x] 2.3 Add `asBus :: AppBus` field to `AppState` in `CLI/App.hs`; create the bus in `mkAppState` (or at startup before entering the REPL)
- [x] 2.4 Replace inline `repoLogCommand` call in CLI REPL with `publish` on `busCommands`

## 3. Audit Subscriber

- [x] 3.1 Add `repoLogCommandWithSource :: String -> String -> String -> IO ()` to the `Repository` record and implement in `Repo/SQLite.hs`
- [x] 3.2 Implement `registerAuditSubscriber :: TopicBus CommandEvent -> Repository -> IO SubscriptionId`
- [x] 3.3 Register the audit subscriber at CLI startup (before the REPL loop) and at server startup

## 4. Terminal Echo Subscriber

- [x] 4.1 Register a terminal echo subscriber at CLI startup with pattern `".*"` that prints `ceCommand` when `ceSource /= CLI`

## 5. Skill Create Guard

- [x] 5.1 Change `sqlCreateSkill` from `INSERT OR REPLACE` to existence check + `INSERT`; return an error (via `Either String ()` or exception) when the ID already exists
- [x] 5.2 Update `Service.Worker.addSkill` to propagate the error
- [x] 5.3 Update the CLI `SkillCreate` handler to display the error message
- [x] 5.4 Update the RPC `rpcCreateSkill` handler to return an error response on duplicate

## 6. Skill Rename Command

- [x] 6.1 Add `SkillRename Int String` to the `Command` type in `CLI/Commands.hs`
- [x] 6.2 Add parse case in `parseCommand`
- [x] 6.3 Add handler case in `handleCommand` (calls `repoRenameSkill`, requires admin)
- [x] 6.4 Add classification case in `classify` for `"skill rename"`
- [x] 6.5 Add RPC endpoint and handler for skill rename; publish `CommandEvent` instead of calling `logRpc`

## 7. Migrate RPC Skill Handlers to Publish

- [x] 7.1 Thread `busCommands` (or `AppBus`) into the RPC server alongside `Repository`
- [x] 7.2 Replace `logRpc` calls in skill-related RPC handlers (`rpcCreateSkill`, `rpcDeleteSkill`) with `publishCommand`
- [x] 7.3 Keep `logRpc` for non-skill RPC handlers (they migrate in a follow-up)

## 8. Migrate Optimizer to TopicBus

- [x] 8.1 Change `Service.Optimize.optimizeSchedule` to accept `TopicBus ProgressEvent` instead of `PubSub ProgressEvent`; publish to `Topic "optimize.progress"`
- [x] 8.2 Update CLI optimizer call sites to subscribe on `busProgress` from `AppBus` instead of creating a local bus

## 9. Tests

- [x] 9.1 Unit tests for `TopicBus`: regex matching, wildcard, prefix, no-match, unsubscribe, thread safety
- [x] 9.2 Unit tests for `buildTopic`: full metadata, missing fields, unrecognized command
- [x] 9.3 Unit tests for `CommandEvent` construction and `publishCommand`
- [x] 9.4 Integration test: audit subscriber writes correct audit_log rows for CLI and RPC events
- [x] 9.5 Integration test: skill create rejects duplicate ID
- [x] 9.6 Integration test: skill rename via CLI and RPC
- [x] 9.7 Verify existing optimizer tests pass with `TopicBus` signature
- [x] 9.8 Verify existing audit tests pass (audit_log schema unchanged)

## 10. Cleanup

- [ ] 10.1 Remove `repoLogCommand` and `repoLogRpcCommand` from the `Repository` record and SQLite implementation (deferred: still used by test helpers)
- [x] 10.2 Remove `logRpc` helper from `Server/Rpc.hs` — all RPC and REST handlers now publish via the bus
- [x] 10.3 Run `stack clean && stack build` and fix all warnings
- [x] 10.4 Verify the demo still works

## 11. Follow-up (separate changes)

- [ ] 11.1 Fix demo script: draft commands use hardcoded IDs that don't match auto-increment; capture IDs from `draft create` output instead (pre-existing issue, not caused by this change)
- [ ] 11.2 Remove `repoLogCommand` and `repoLogRpcCommand` once test helpers are migrated to use the bus
