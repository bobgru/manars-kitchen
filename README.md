# Manar's Kitchen

A restaurant employee scheduling system built in Haskell. It generates
weekly schedules that satisfy hard constraints (skills, hours, rest
periods) while optimizing soft preferences (station preferences, shift
preferences, workload balance). A web interface and interactive CLI
provide schedule generation, what-if analysis, diagnosis of coverage
gaps, and full audit logging backed by SQLite.

## Quick start

Prerequisites:

- [Stack](https://docs.haskellstack.org/) (GHC 9.10 / LTS 24.35)
- [Node.js](https://nodejs.org/) (for building the web frontend)
- Python 3 (used by the demo script)

```
make build          # compile library + CLI + server
make test           # run all tests
make demo           # replay the demo restaurant setup (with delay)
make fast-demo      # same, instant replay
make run            # launch interactive CLI REPL
make server         # start the web server
make clean          # remove databases and build artifacts
```

The demo replays `demo/restaurant-setup.txt`, which configures a
restaurant with 7 stations, 8 skills, 11 workers, and 5 shift blocks,
then generates and reviews a multi-week schedule. On completion, the demo
automatically exports `demo-export.json` which can be imported into an
interactive session via `import demo-export.json`. Databases are stored
in `demo-db/` (demos) and `run-db/` (interactive sessions).

### Web interface

Build the frontend and start the server:

```
make web
make server
```

Then open http://localhost:8080 in a browser. Log in as `admin/admin`
(created automatically on first run). The web terminal accepts the
same commands as the CLI.

During development, you can run the Vite dev server for hot reload:

```
cd web && npm run dev
```

This serves the frontend on http://localhost:5173 and proxies `/api`
and `/rpc` requests to the backend at http://localhost:8080 (start
`make server` in a separate terminal).

### Interactive CLI session

```
$ make run
manars> help                  # show command groups
manars> help schedule         # show commands in a group
```

Log in as `admin/admin` (created automatically). From there you can
define shifts, skills, stations, and workers, then generate and review
schedules. Every admin command is recorded in the audit log and can be
replayed.


## CLI Features

### Two-level help

The `help` command shows a summary of command groups. Use
`help <group>` to see the commands in a group:

```
manars> help
Command groups (type 'help <group>' for details):

  schedule    Schedule creation, viewing, and management
  worker      Worker skills, hours, preferences, and pairings
  skill       Skill definitions and implications
  station     Station setup, hours, and requirements
  ...

manars> help schedule
  schedule list                   List saved schedules
  schedule view <name>            View a schedule (table)
  schedule view-by-worker <name>  View schedule grouped by worker
  schedule view-compact <name>    View schedule (compact, 100-col)
  schedule diagnose <name>        Diagnose unfilled positions
  ...
```

### Name-based entity references

Commands that take worker, skill, station, or absence-type IDs also
accept entity names. Names are matched case-insensitively:

```
worker grant-skill marco grill    # same as: worker grant-skill 2 1
station set-hours grill 10 17     # same as: station set-hours 1 10 17
```

If the input is numeric it is used as-is; otherwise the CLI looks up
the name and substitutes the ID before dispatching.

### Session context

Use `use <type> <name>` to set a default entity. Once set, type `.`
in place of an ID to refer to it:

```
manars> use worker marco
Context set: worker = marco (#2)

manars> worker set-hours . 40       # same as: worker set-hours 2 40
manars> worker set-overtime . on    # same as: worker set-overtime 2 on

manars> context view
  worker  marco (#2)

manars> context clear
```

### Compact schedule display

`schedule view-compact` shows the same data as `schedule view` in a
narrower format (fits in 100 columns) using abbreviated worker names:

```
schedule view-compact week1
```

### Checkpoints

Checkpoints let you try changes and undo them if needed. They use
SQLite savepoints, so they are lightweight and instant:

```
manars> checkpoint create before-overtime
Checkpoint created: before-overtime

manars> worker set-overtime 2 on
manars> schedule create week1-v2 2026-04-06

manars> checkpoint rollback before-overtime
Rolled back to: before-overtime

manars> checkpoint list
  (no active checkpoints)
```

`checkpoint commit` releases the most recent checkpoint, making its
changes permanent. `checkpoint rollback` without a name rolls back
the most recent checkpoint.


## Workflow

### 1. Define the restaurant

Set up the building blocks before generating any schedule.

**Shifts** define named time windows used for grouping slots and
expressing worker preferences:

```
shift create morning 6 10
shift create midday 10 14
shift create afternoon 14 18
```

**Skills** represent capabilities. They form a preorder: if skill A
implies skill B, any worker with A is also qualified for B. The closure
is transitive (A implies B implies C means A qualifies for C).

```
skill create 1 grill
skill create 2 prep
skill implication 1 2        # grill implies prep
```

**Stations** are positions that need to be staffed. Each station
requires one or more skills and has configurable operating hours:

```
station add 1 grill
station require-skill 1 1    # grill station requires grill skill
station set-hours 1 10 17    # open 10am-5pm
station set-multi-hours 1 10 12   # allow multi-station 10am-12pm
station close-day 1 sunday        # closed Sundays
```

### 2. Configure workers

Create user accounts and assign skills, hour limits, and preferences:

```
user create marco changeme normal
worker grant-skill 2 1           # Marco gets grill skill
worker set-hours 2 40            # 40h/week max
worker set-prefs 2 1 3           # prefers grill, then sandwich
worker set-shift-pref 2 morning midday
worker set-seniority 2 2         # experienced
worker set-overtime 2 on         # can exceed limit when needed
```

**Employment status** sets sensible defaults for hour limits, overtime
eligibility, and time tracking:

| Status | Overtime | Tracking | Default hours |
|--------|----------|----------|---------------|
| `full-time` | eligible | standard | 40 |
| `salaried` | manual-only | standard | 40 |
| `per-diem` | exempt | exempt | no limit |

```
worker set-status 2 salaried     # Marco: salaried manager
worker set-status 3 per-diem     # Lucia: per-diem floater
worker set-temp 11 on            # Pat: temp worker
worker set-overtime-model 7 manual-only  # override default
```

Other worker options:

| Command | Effect |
|---------|--------|
| `worker set-variety <w> on` | Prefer station rotation day to day |
| `worker set-weekend-only <w> on` | Only schedule on weekends |
| `worker set-cross-training <w> <skill>` | Learning goal (needs mentor) |
| `worker avoid-pairing <w1> <w2>` | Never assign at same slot |
| `worker prefer-pairing <w1> <w2>` | Bonus for working together |

### 3. Manage absences

Define absence types, set yearly allowances, and process requests:

```
absence-type create 1 vacation on    # capped type (has yearly limit)
absence set-allowance 9 1 10         # Worker 9 gets 10 vacation days
absence request 1 9 2026-04-10 2026-04-10
absence approve 1
```

Uncapped types (training, maternity) have no yearly limit. Approval of
capped types checks remaining allowance; `approve-override` bypasses the
check.

### 4. Generate a schedule

```
schedule create week1 2026-04-06
```

This generates 1-hour slots for the week containing the given date,
then runs the multi-phase scheduling algorithm. The result includes
assignments, unfilled positions, and overtime hours.

### 5. Review

```
schedule view week1              # time-slot grid
schedule view-by-worker week1    # grouped by worker
schedule view-by-station week1   # grouped by station
schedule hours week1             # per-worker hour summary
schedule diagnose week1          # coverage analysis + suggestions
```

The diagnosis engine classifies each unfilled position (no qualified
workers, all busy, all over hours, all absent) and ranks actionable
suggestions: hire for a skill, train a specific worker, allow overtime,
or close a station.

### 6. Pinned assignments

Pins are recurring weekly constraints. A pin locks a worker to a
station on a given weekday, either at a specific hour or for an entire
shift:

```
pin 2 1 monday morning     # Marco on grill every Monday morning
pin 5 4 friday 14          # Maria on beverage every Friday at 2pm
```

Pinned assignments are used as a seed schedule: the greedy algorithm
fills around them.

### 7. Calendar and drafts

The **calendar** is a continuous timeline of committed schedules. Once
a schedule is committed, it becomes the official record for that date
range.

```
calendar commit week1 2026-04-06 2026-04-12 initial week 1
calendar view 2026-04-06 2026-04-12
calendar hours 2026-04-06 2026-04-12
calendar history
```

**Drafts** are non-overlapping weekly schedules under development.
Create a draft, generate a schedule inside it, review, and commit when
ready:

```
draft create 2026-04-13 2026-04-19
draft generate 1
draft view-compact 1
draft hours 1
draft commit 1 week 2 via draft
```

Drafts support **cross-draft validation**: when you commit one draft
and then re-open another, the system detects that the calendar changed
and re-validates all assignments. For example, workers who worked a
weekend in a newly committed draft will have their next-weekend
assignments automatically removed (alternating weekends rule).

The **freeze line** protects historical calendar dates. Dates on or
before the freeze line (default: yesterday) are frozen -- creating a
draft that covers them triggers a warning. Two workflows allow
intentional history edits:

```
# Option 1: force-create the draft
draft create 2026-04-06 2026-04-12 --force

# Option 2: explicitly unfreeze, then create normally
calendar unfreeze 2026-04-06 2026-04-12
draft create 2026-04-06 2026-04-12
```

Temporary unfreezes auto-clear after committing a draft that includes
historical dates.

### 8. What-if exploration

Within a draft session, the **what-if** system lets you explore
hypothetical changes without modifying any real data:

```
what-if grant-skill nina grill          # what if Nina could grill?
what-if close-station pizza 2026-04-27 11  # what if pizza closed Mon 11am?
what-if list                            # review active hints
what-if revert                          # undo most recent hint
what-if revert-all                      # clear all hints
```

Each hint shows a diff of the schedule impact. Hints are composable
and fully reversible -- nothing is persisted until you commit.

### 9. Pay periods

Configure pay periods to track per-period hour limits:

```
config set-pay-period biweekly 2026-04-06
config show-pay-period
```

### 10. Import / export

```
export week1 schedule.json    # export one schedule
export all-data.json          # export everything
import backup.json            # merge into current database
import demo-export.json       # import data from a demo run
```


## Configuration

All scoring weights and rule thresholds are tunable at runtime through
22 parameters stored in the database. Three presets are available.

```
config show                        # display current values
config set capacity-multiplier 150 # change a parameter
config preset preference-first     # apply a preset
config reset                       # restore defaults
```

### Scoring parameters

These weights control how the soft-constraint scoring function ranks
candidate workers. Higher total score = more preferred assignment.

| Parameter | Default | Effect |
|-----------|---------|--------|
| `shift-pref-bonus` | 12.0 | Bonus when slot falls in worker's preferred shift |
| `weekend-pref-bonus` | 8.0 | Bonus for weekend preference on Sat/Sun |
| `station-pref-base` | 10.0 | Base score for rank-0 station preference (decreases by 1 per rank) |
| `coverage-multiplier` | 15.0 | Multiplied by fraction of shift slots the worker can cover |
| `capacity-multiplier` | 100.0 | Multiplied by fraction of weekly hours remaining (dominates to spread load) |
| `over-limit-penalty` | -100.0 | Penalty when worker is at or over their hour limit |
| `no-limit-capacity` | 5.0 | Small bonus for workers with no hour limit |
| `variety-bonus` | 3.0 | Bonus for a station the worker hasn't worked in the last 3 days |
| `variety-penalty` | -3.0 | Penalty for a recently-worked station (variety-preferring workers) |
| `multi-station-bonus` | 8.0 | Bonus when worker is already assigned at the same slot (multi-station) |
| `cross-training-bonus` | 6.0 | Bonus for pairing workers of different seniority at a slot |
| `cross-training-goal-bonus` | 8.0 | Bonus for assigning a worker to a cross-training goal station with mentor present |
| `pairing-bonus` | 5.0 | Bonus per preferred coworker already at the slot |

### Hard constraint thresholds

| Parameter | Default | Effect |
|-----------|---------|--------|
| `max-daily-regular-hours` | 8.0 | Maximum regular (non-overtime) hours per day |
| `max-daily-total-hours` | 16.0 | Maximum total hours per day including overtime |
| `max-consecutive-hours` | 4.0 | Maximum consecutive hours before a mandatory break |
| `min-rest-hours` | 8.0 | Minimum rest between end of one day and start of next |

### Optimization parameters

| Parameter | Default | Effect |
|-----------|---------|--------|
| `opt-enabled` | 0.0 | Set to 1.0 to enable the optimization loop |
| `opt-time-limit-secs` | 30.0 | Wall-clock time limit for the optimizer |
| `opt-randomness` | 0.3 | Perturbation magnitude (0.0 = deterministic, 1.0 = maximum noise) |
| `opt-progress-interval` | 5.0 | Seconds between progress reports (0.0 = silent) |
| `greedy-strategy` | 0.0 | Greedy fill order (see Algorithms below) |

### Presets

| Preset | Philosophy |
|--------|------------|
| `balanced` | Default. Even mix of capacity-spreading and preference satisfaction. |
| `preference-first` | Heavier weight on shift and station preferences; less aggressive load balancing. |
| `capacity-first` | Extreme capacity multiplier; spreads hours as evenly as possible at the cost of preference matching. |


## Scheduling rules

### Hard constraints

An assignment is blocked if **any** of the following conditions hold:

1. **Skill qualification** -- Worker lacks a skill required by the
   station (accounting for transitive implications), unless the station
   is a cross-training goal with a mentor present at the same slot.
2. **Absence** -- Worker has an approved absence covering that day.
3. **Multi-station conflict** -- Worker is already assigned to a
   different station at the same slot, and the slot is not within the
   station's multi-station hours (or the worker's seniority doesn't
   permit it).
4. **Avoid pairing** -- A worker in the avoid-pairing set is already
   assigned at that slot.
5. **Daily regular hours** -- Assignment would push the worker past
   `max-daily-regular-hours`.
6. **Daily total hours** -- Assignment would push past
   `max-daily-total-hours` (even with overtime).
7. **Consecutive hours** -- Worker has worked `max-consecutive-hours`
   without a break.
8. **Rest period** -- Insufficient gap (`min-rest-hours`) since the
   worker's last assignment on the previous day.
9. **Weekly hours** -- Assignment would exceed the worker's weekly hour
   limit, unless overtime is allowed in the current phase and the worker
   has opted in.
10. **Alternating weekends** -- Worker worked the previous weekend and
    is not a weekend-only worker.

### Soft constraints

When multiple workers satisfy all hard constraints for a slot, the
scoring function ranks them. The score is a weighted sum of the factors
listed in the configuration table above. The worker with the highest
score is chosen.

The `capacity-multiplier` parameter dominates by default (100.0 vs
5-15 for other factors), which ensures that hours are spread evenly
across the team before preferences are considered.


## Algorithms

### Schedule generation

Schedule generation runs in three phases. All phases use the same hard
constraint checks; they differ in overtime policy and slot granularity.

**Phase 1 -- Greedy shift fill (no overtime).** Slots are grouped into
shift blocks (e.g., morning 6-10, midday 10-14). For each block, each
station that needs a worker is considered. The best-scoring qualified
worker is picked and assigned to all slots in the block that they can
work (respecting breaks, daily limits, rest). Phase 1 never allows
assignments that exceed a worker's weekly hour limit.

**Phase 2 -- Retry unfilled (with overtime).** Positions left unfilled
after Phase 1 are retried at slot-level granularity. Workers who have
opted in to overtime can now exceed their weekly limit.

**Phase 3 -- Gap fill.** A final pass at individual unfilled slots,
used for floater coverage and break relief.

### Greedy strategies

Five strategies control the order in which Phase 1 visits stations and
blocks. The strategy is selected by the `greedy-strategy` config
parameter (0-4). When the optimizer is enabled, it tries all five
strategies for the initial schedule and picks the best, then varies the
strategy randomly on each optimization iteration.

| Value | Name | Description |
|-------|------|-------------|
| 0 | Bottleneck-first | Sorts stations by fewest qualified candidates (MRV heuristic). Most constrained stations get first pick of workers. Default for standalone use. |
| 1 | Chronological | Processes shift blocks and stations in natural order. Early shifts and low-numbered stations get priority. |
| 2 | Reverse-chronological | Processes shift blocks in reverse order. Later shifts get priority. |
| 3 | Random shuffle | Fisher-Yates shuffle of both block order and station order within each block, driven by the perturbation stream. |
| 4 | Worker-first | Inverts the loop: iterates workers sorted by constraint level (fewest qualified stations first), greedily assigning each worker to their best available (block, station) pair until their hours are exhausted. |

### Optimization

When `opt-enabled` is set to 1.0, schedule generation is followed by a
two-phase optimization loop that runs until the time limit
(`opt-time-limit-secs`) is reached.

**Phase 1 -- Hard constraint improvement (iterated greedy).** The goal
is to reduce the number of unfilled positions. Each iteration:

1. Identifies a *neighborhood*: assignments at the same slot as
   unfilled positions, plus same-worker assignments on the same day.
2. Randomly destroys part of the neighborhood (removal probability
   controlled by `opt-randomness`), preserving pinned assignments.
3. Rebuilds the schedule from scratch using a randomly chosen greedy
   strategy with perturbed scoring (noise magnitude proportional to
   `opt-randomness`).
4. Keeps the new schedule if it has fewer unfilled positions.

This phase ends when all positions are filled or time runs out.

**Phase 2 -- Soft constraint improvement (hill climbing).** Once all
hard constraints are satisfied, the optimizer tries to improve the total
soft score by proposing worker swaps:

1. At each slot with two or more assigned workers, propose swapping
   their stations.
2. Validate that both workers satisfy all hard constraints at their new
   stations.
3. Accept the swap if the total schedule score improves.

The optimizer reports progress at configurable intervals, showing the
current iteration count, unfilled count (Phase 1) or best score
(Phase 2), and elapsed time.

### Strictness

The optimization loop uses bang patterns and deep forcing
(`Set.foldl'`, `Map.foldl'`) to prevent thunk accumulation across
iterations. Each iteration's result is fully evaluated before the next
begins, ensuring constant memory usage regardless of iteration count.


## Project structure

```
server-app/
  Main.hs                    HTTP server entry point (Warp + static files)

web/
  src/
    api/client.ts            Fetch wrapper with auth token injection
    api/execute.ts           POST /rpc/execute caller
    components/LoginPage.tsx Login form
    components/Terminal.tsx   Command terminal with history and paste
    components/AppShell.tsx   App layout (header + terminal)
    App.tsx                  Root component (auth routing)

cli/
  Main.hs                    CLI entry point (REPL + demo mode)
  CLI/RpcClient.hs           Remote mode RPC dispatch

src/
  CLI/
    App.hs                   Command dispatch, help, demo replay
    Commands.hs              Command parser
    Display.hs               Formatted output (tables, hours, diagnosis)
    Resolve.hs               Entity name resolution, session context
  Server/
    Api.hs                   Servant API type definitions
    Auth.hs                  Login/logout, session token validation
    Handlers.hs              REST endpoint handlers
    Rpc.hs                   RPC endpoint handlers
    Execute.hs               Web terminal command execution (stdout capture)
    Json.hs                  JSON request/response types
    Error.hs                 HTTP error responses

  Domain/
    Types.hs                 Core types (Schedule, Assignment, Slot, IDs)
    Schedule.hs              Assign/unassign operations (monoid)
    Transaction.hs           Reassign, swap operations
    Skill.hs                 Skill preorder, qualification checks
    Worker.hs                Hour limits, preferences, break/rest rules
    Scheduler.hs             Multi-phase greedy algorithm, scoring
    SchedulerConfig.hs       22 tunable parameters, presets
    Optimizer.hs             Neighborhood destruction, hill climbing
    Shift.hs                 Shift blocks, grouping
    Calendar.hs              Slot generation (week/month/range)
    Absence.hs               Absence lifecycle, allowances
    Hint.hs                  What-if sessions, reversible hints
    Diagnosis.hs             Unfilled analysis, suggestions
    Pin.hs                   Recurring pinned assignments
    PayPeriod.hs             Pay period tracking
  Service/
    Auth.hs                  Login, user management
    Schedule.hs              Schedule CRUD (repo-backed)
    Worker.hs                Worker configuration (repo-backed)
    Absence.hs               Absence operations (repo-backed)
    Config.hs                Config persistence
    Optimize.hs              Optimization loop orchestration
    Calendar.hs              Calendar timeline operations
    Draft.hs                 Draft schedule management
    DraftValidation.hs       Cross-draft constraint re-validation
    FreezeLine.hs            Historical date guardrail
  Repo/
    Types.hs                 Repository interface
    Schema.hs                SQLite schema
    Serialize.hs             JSON serialization for complex types
    SQLite.hs                Database queries and mutations
  Auth/
    Types.hs                 User, role types
    Password.hs              Bcrypt hashing
  Export/
    JSON.hs                  Full import/export

test/
  Spec.hs                    Test harness (546 examples)
  CalendarSpec.hs            Calendar operations
  DraftSpec.hs               Draft lifecycle
  DraftValidationSpec.hs     Cross-draft constraint checks
  FreezeLineSpec.hs          Freeze line guardrails
  HintIntegrationSpec.hs     What-if exploration

demo/
  restaurant-setup.txt       Example restaurant configuration script
```

## Testing

The test suite covers domain logic with both property-based tests
(QuickCheck) and example-based tests (Hspec):

- **Schedule algebra**: assign/unassign laws, monoid laws, projections
- **Transactions**: reassign decomposition, swap involution
- **Skills**: transitive closure, qualification checks
- **Workers**: hour tracking, overtime, daily limits, breaks, rest periods, preferences
- **Scheduler**: coverage, skill enforcement, unfilled reporting, overtime, seeded schedules
- **Absences**: request lifecycle, allowance enforcement, availability
- **Hints**: session management, all 6 hint types, composition
- **Diagnosis**: reason classification, suggestion ranking
- **Calendar**: slot generation, closed dates, day-of-week hours
- **Drafts**: create/generate/commit lifecycle, discard
- **Draft validation**: cross-draft constraint re-validation, alternating weekends
- **Freeze line**: freeze/unfreeze lifecycle, force-create, auto-refreeze
- **Shifts**: grouping, overlapping blocks
- **Config**: round-trip serialization, presets, completeness
- **Pins**: slot-level and shift-level expansion
- **Optimizer**: scoring, neighborhood operations, swap validation, hill climbing

```
make test
```
