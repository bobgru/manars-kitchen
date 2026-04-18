# Design: Topic-Routed Pub/Sub with Typed Channels

## Context

The existing `PubSub e` bus is a flat typed event bus — every subscriber receives every event. It works for optimizer progress (one publisher, one subscriber, one event type) but cannot support the cross-cutting observation pattern needed for UI sync: multiple publishers (CLI, RPC), multiple subscribers (audit, terminal echo, web UI), filtering by domain topic.

The audit log is written inline at two sites: `repoLogCommand` in the CLI REPL loop (`CLI/App.hs:119`) and `logRpc` in each RPC handler (`Server/Rpc.hs:449`). Both call `classify` to extract `CommandMeta`, but the wiring is duplicated.

This change builds the full vertical slice for **skills** — bus infrastructure, command events, audit-as-subscriber, terminal echo, and the skill create/rename fix. Other entities replicate the same pattern in follow-up changes.

## Architecture

```
┌──────────────┐        ┌──────────────┐
│   CLI REPL   │        │  RPC Handler │
│              │        │              │
│  build       │        │  build       │
│  CommandEvent│        │  CommandEvent│
│  + Topic     │        │  + Topic     │
└──────┬───────┘        └──────┬───────┘
       │                       │
       ▼                       ▼
┌──────────────────────────────────────┐
│         AppBus                       │
│  ┌────────────────────────────────┐  │
│  │ busCommands :: TopicBus        │  │
│  │              CommandEvent      │  │
│  │                                │  │
│  │  ┌──── regex ──── callback ──┐ │  │
│  │  │ ".*"          auditWrite  │ │  │
│  │  │ ".*"          termEcho    │ │  │
│  │  │ "skill\\..*"  webRefresh  │ │  │
│  │  └──────────────────────────-┘ │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │ busProgress :: TopicBus        │  │
│  │              ProgressEvent     │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

## Key decisions

### TopicBus replaces PubSub — same module, new API

Evolve `Service.PubSub` in place rather than creating a parallel module. The `TopicBus e` type replaces `PubSub e`. The API changes:

```haskell
-- Old
subscribe :: PubSub e -> (e -> IO ()) -> IO SubscriptionId
publish   :: PubSub e -> e -> IO ()

-- New
subscribe :: TopicBus e -> String -> (Topic -> e -> IO ()) -> IO SubscriptionId
publish   :: TopicBus e -> Topic -> e -> IO ()
```

Subscribers provide a regex pattern as a `String`. The bus pre-compiles it to a `Regex` at subscription time and matches against it on each publish. Callbacks receive `(Topic, e)` so they can inspect which specific topic fired.

`newTopicBus` replaces `newPubSub`. The internal structure gains a compiled regex per subscriber:

```haskell
newtype Topic = Topic String deriving (Eq, Ord, Show)

data TopicBus e = TopicBus
    { tbNextId      :: !(MVar Int)
    , tbSubscribers :: !(MVar (Map Int (Regex, Topic -> e -> IO ())))
    }
```

### AppBus container holds typed channels

```haskell
data AppBus = AppBus
    { busCommands :: !(TopicBus CommandEvent)
    , busProgress :: !(TopicBus ProgressEvent)
    }

newAppBus :: IO AppBus
newAppBus = AppBus <$> newTopicBus <*> newTopicBus
```

The existing optimizer code migrates from `PubSub ProgressEvent` to `TopicBus ProgressEvent`. It publishes to topic `"optimize.progress"` instead of broadcasting. Subscriber registration adds a `".*"` pattern (functionally equivalent to the old behavior).

### CommandEvent type

```haskell
data Source = CLI | RPC | Demo deriving (Eq, Show)

data CommandEvent = CommandEvent
    { ceCommand  :: !String        -- human-readable: "skill create 4 grill"
    , ceMeta     :: !CommandMeta   -- structured fields from classify
    , ceSource   :: !Source        -- who published
    , ceUsername :: !String        -- authenticated user
    }
```

`CommandMeta` is reused unchanged from `Audit.CommandMeta`.

### Topic construction from CommandMeta

A pure function builds the topic string from structured metadata:

```haskell
buildTopic :: CommandMeta -> Topic
buildTopic meta = Topic $ intercalate "." $ catMaybes
    [ cmEntityType meta
    , cmOperation meta
    , fmap show (cmEntityId meta)
    ]
```

Examples:
- `classify "skill create 4 grill"` → `Topic "skill.create.4"`
- `classify "worker grant-skill 3 5"` → `Topic "worker.grant-skill.3"`
- `classify "draft commit 7"` → `Topic "draft.commit.7"`

When `cmEntityType` or `cmOperation` is `Nothing` (unrecognized command), `buildTopic` produces a partial or empty topic. The `".*"` audit subscriber still matches; narrower subscribers naturally ignore it.

### Active-listener guard via ceSource

Subscribers that are also publishers filter on `ceSource` to avoid reacting to their own events:

- **Terminal echo**: callback checks `ceSource /= CLI` before printing
- **Web UI refresh**: JavaScript checks `event.source !== "rpc"` before refetching
- **Audit writer**: no filter — logs everything

A future `Demo` source benefits automatically: both the terminal and web UI will display demo-originated events since neither filters on `Demo`.

This prevents the "active-listener" infinite loop without complicating the bus itself. The filtering is the subscriber's responsibility, not the bus's.

### Audit logging becomes a subscriber

Replace inline `repoLogCommand` / `logRpc` calls with a single audit subscriber:

```haskell
registerAuditSubscriber :: TopicBus CommandEvent -> Repository -> IO SubscriptionId
registerAuditSubscriber bus repo =
    subscribe bus ".*" $ \_topic event ->
        repoLogCommandEvent repo event
```

Where `repoLogCommandEvent` is a new Repository function that writes the audit row from `CommandEvent` fields (command text, metadata, source, username).

The two existing functions `repoLogCommand` (source=cli) and `repoLogRpcCommand` (source=rpc) are replaced by this single path. The `source` column value comes from `ceSource`.

### Publishing from the CLI REPL

Currently (`CLI/App.hs:118-120`):

```haskell
when (isMutating cmd) $ do
    repoLogCommand (asRepo st) uname line
    repoTouchSession (asRepo st) (asSessionId st)
```

Becomes:

```haskell
when (isMutating cmd) $ do
    let meta = classify line
        topic = buildTopic meta
        event = CommandEvent line meta CLI uname
    publish (busCommands (asBus st)) topic event
    repoTouchSession (asRepo st) (asSessionId st)
```

`AppState` gains an `asBus :: AppBus` field so the bus is available throughout the REPL.

### Publishing from RPC handlers

Currently each handler calls `logRpc` individually:

```haskell
rpcCreateSkill repo req = do
    liftIO $ SW.addSkill repo (SkillId (csrId req)) (csrName req) (csrDescription req)
    logRpc repo ("skill create " ++ show (csrId req) ++ " " ++ csrName req)
    pure RpcOk
```

Becomes:

```haskell
rpcCreateSkill bus repo req = do
    liftIO $ SW.addSkill repo (SkillId (csrId req)) (csrName req) (csrDescription req)
    publishCommand bus RPC "rpc" ("skill create " ++ show (csrId req) ++ " " ++ csrName req)
    pure RpcOk
```

Where `publishCommand` is a helper:

```haskell
publishCommand :: TopicBus CommandEvent -> Source -> String -> String -> IO ()
publishCommand bus source username cmdStr = do
    let meta = classify cmdStr
        topic = buildTopic meta
        event = CommandEvent cmdStr meta source username
    publish bus topic event
```

The `AppBus` (or just `busCommands`) is threaded into the RPC server alongside `Repository`. The `logRpc` helper is retired.

### Synchronous delivery guarantees no lost events

The `publish` function calls each matching subscriber's callback sequentially in the publisher's thread:

```
publish(topic, event)
  ├─ call auditWrite(event)   ← publisher blocks until row is written
  │     └─ returns
  ├─ call termEcho(event)     ← publisher blocks until print completes
  │     └─ returns
  └─ publish returns to caller
```

There is no intermediate queue, buffer, or async hand-off. An event is delivered to every matching subscriber before `publish` returns. Events cannot be lost due to a fast publisher outpacing a slow consumer — the publisher *is* the consumer's thread.

This is a deliberate choice. A queue-based design would introduce the very lost-event risk it aims to solve: a bounded queue can overflow and drop, an unbounded queue can grow without limit. The synchronous model trades publisher latency for delivery certainty.

The tradeoff is that a slow subscriber blocks the publisher and all subsequent subscribers. For the current use cases (audit SQLite write, terminal print, UI refresh signal) this is fine — all are fast local operations. If a future subscriber involves slow I/O (e.g., SSE network write), it should `forkIO` internally to avoid blocking the chain. The bus itself stays simple.

### Terminal echo subscriber

Registered in the CLI startup, alongside the audit subscriber:

```haskell
subscribe (busCommands bus) ".*" $ \_ event ->
    when (ceSource event /= CLI) $
        putStrLn ("[echo] " ++ ceCommand event)
```

When an RPC handler publishes a command event, the terminal prints it. When the CLI itself publishes, the guard suppresses the echo.

### Web UI refresh (future wiring)

Not implemented in this change, but the pattern is established. When SSE or WebSocket support is added, the server subscribes to `busCommands` and forwards matching events to connected browsers. The JavaScript handler checks `event.source !== "rpc"` and triggers a refetch.

For now, the web UI continues to require manual refresh to see CLI-originated changes.

### Skill create: reject duplicate IDs

Change `repoCreateSkill` from `INSERT OR REPLACE` to `INSERT` with a prior existence check:

```sql
-- Check
SELECT COUNT(*) FROM skills WHERE id = ?
-- If exists: error
-- If not: INSERT INTO skills (id, name, description) VALUES (?, ?, ?)
```

The CLI handler and RPC handler surface the error to the user:

```
manars> skill create 4 grill
Error: Skill 4 already exists ("grill"). Use 'skill rename 4 <new-name>' to rename.
```

### Skill rename CLI command

Wire `repoRenameSkill` (already exists in the repo layer) to a new `SkillRename` command:

```
manars> skill rename 4 "sauté"
Renamed skill 4 to "sauté"
```

This requires:
- `SkillRename Int String` constructor in the `Command` type
- Parser case in `parseCommand`
- Handler case in `handleCommand`
- Classification case in `classify` → `CommandMeta { entityType = "skill", operation = "rename", entityId = 4 }`

### Migration of existing PubSub ProgressEvent

The optimizer currently creates a local `PubSub ProgressEvent` bus per command invocation. This migrates to using `busProgress` from the `AppBus`:

```haskell
-- Before
bus <- newPubSub
subId <- subscribe bus $ \evt -> ...
result <- Opt.optimizeSchedule ctx seed bus

-- After
subId <- subscribe (busProgress (asBus st)) ".*" $ \_topic evt -> ...
result <- Opt.optimizeSchedule ctx seed (busProgress (asBus st))
```

The optimizer changes from `publish bus (OptimizeProgress p)` to `publish bus (Topic "optimize.progress") (OptimizeProgress p)`.

### Propagation to other entities

This change establishes the pattern with skills. Other entities (stations, workers, shifts, absences, etc.) have the same shape:

1. Fix upsert semantics → reject duplicate on create
2. Add rename CLI command if missing
3. Replace inline `logRpc` with `publishCommand` in RPC handlers

The CLI side needs no per-entity work — it already publishes all mutating commands generically. The RPC side needs per-handler updates because each handler constructs its own command string. A follow-up change should propagate the pattern to all RPC handlers.

## Risks / Trade-offs

**[Regex matching on every publish]** Each publish iterates all subscribers and tests the topic against each compiled regex. With single-digit subscriber counts and simple patterns, this is negligible. If subscriber counts grow significantly, a trie-based routing structure could replace linear scan — but that's over-engineering for now.

**[Audit write is no longer inline]** If the bus has a bug (e.g., subscriber map is corrupted), audit entries could be silently lost. Mitigation: the bus is simple MVar-protected code with thorough tests. The audit subscriber is registered first and runs synchronously. If this proves fragile in practice, we can add a fallback inline write.

**[CLI logging moves from before to during command handling]** Currently `repoLogCommand` runs before `handleCommand`. With the new design, the CLI publishes after building the event (still before handling). The timing is equivalent, but the code path changes. Verify in tests that audit entries appear for commands that fail during handling.

**[Thread safety of terminal echo]** The terminal echo callback writes to stdout from the pub/sub publish thread. If the CLI is in the middle of printing command output, the echo could interleave. In practice, RPC-originated events only arrive from the web server thread, and the CLI command handler runs synchronously — so interleaving is unlikely. However, thread-safe terminal output (an MVar-protected write function that serializes all stdout access) should be added as a high-priority near-term follow-up. This is a prerequisite for reliable echo behavior and will also benefit optimizer progress output and any future concurrent output sources.
