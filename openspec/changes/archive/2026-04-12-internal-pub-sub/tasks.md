## 1. PubSub Module

- [x] 1.1 Create `src/Service/PubSub.hs` with `PubSub e`, `SubscriptionId`, `newPubSub`, `subscribe`, `unsubscribe`, `publish` using MVar-protected callback map
- [x] 1.2 Add `Service.PubSub` to the library's exposed-modules in `manars-kitchen.cabal`

## 2. ProgressEvent Type and Optimizer Refactor

- [x] 2.1 Define `ProgressEvent` sum type (with `OptimizeProgress OptProgress` constructor) in a suitable module (e.g., `Service.PubSub` or `Service.Progress`)
- [x] 2.2 Change `optimizeSchedule` signature to accept `PubSub ProgressEvent` instead of `(OptProgress -> IO ())`; publish `OptimizeProgress` events through the bus

## 3. CLI Integration

- [x] 3.1 Update `CLI.App` to create a `PubSub ProgressEvent` bus, subscribe an optimizer progress handler, call `optimizeSchedule` with the bus, and unsubscribe after
- [x] 3.2 Add `stm` or any needed dependency to the `manars-cli` executable build-depends if required (MVar is in base, so likely not needed)

## 4. Tests

- [x] 4.1 Add unit tests for `PubSub`: no-subscriber publish, single subscriber, multiple subscribers, unsubscribe behavior
- [x] 4.2 Verify existing optimizer-related tests compile and pass with the new signature
