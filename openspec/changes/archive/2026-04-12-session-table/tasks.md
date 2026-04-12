## 1. Schema and Types

- [x] 1.1 Add `SessionId` newtype to `Repo/Types.hs`
- [x] 1.2 Add session repo function signatures to `Repository` record: `repoCreateSession`, `repoGetActiveSession`, `repoTouchSession`, `repoCloseSession`
- [x] 1.3 Add `sessions` table DDL to `Repo/Schema.hs`

## 2. SQLite Implementation

- [x] 2.1 Implement `sqlCreateSession` in `Repo/SQLite.hs`
- [x] 2.2 Implement `sqlGetActiveSession` in `Repo/SQLite.hs`
- [x] 2.3 Implement `sqlTouchSession` in `Repo/SQLite.hs`
- [x] 2.4 Implement `sqlCloseSession` in `Repo/SQLite.hs`
- [x] 2.5 Wire session functions into `mkSQLiteRepo`

## 3. CLI Integration

- [x] 3.1 Add `asSessionId` field to `AppState` in `CLI/App.hs`
- [x] 3.2 Update `mkAppState` to accept and store a `SessionId`
- [x] 3.3 Touch session in REPL loop when a mutating command runs
- [x] 3.4 Close session in `Quit` handler
- [x] 3.5 Add session resumption prompt to login flow in `cli/Main.hs`

## 4. Testing

- [x] 4.1 Unit test: create session and retrieve active session
- [x] 4.2 Unit test: close session makes it inactive
- [x] 4.3 Unit test: touch session updates last_active_at
- [x] 4.4 Unit test: multiple sessions — only the active one is returned
