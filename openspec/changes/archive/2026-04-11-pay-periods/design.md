## Context

The system currently enforces worker hour limits on a weekly basis. `WorkerContext.wcMaxWeeklyHours` stores per-worker maximum seconds, and `workerWeeklyHours` computes hours within an ISO week (Monday-Sunday) by scanning the schedule being generated. The `worker_hours` table stores `max_weekly_seconds`. The scheduler's `canAssignSlot` calls `wouldBeOvertime`, which calls `workerWeeklyHours` with only the in-progress draft schedule -- it has no awareness of hours already committed in the calendar.

Change 5 (employment-status) introduces a `pay_period_tracking` field per worker with values `standard` or `exempt`. Per-diem (exempt) workers should not be subject to pay period hour tracking. This change builds on that field.

Change 1 (calendar-foundation) provides `repoLoadCalendar :: Day -> Day -> IO Schedule` which can load committed assignments for any date range. This is the mechanism for retrieving already-committed hours.

## Goals / Non-Goals

**Goals:**
- Define a restaurant-wide pay period (type + anchor date) stored in the database
- Provide domain functions to compute pay period boundaries for any given date
- Make the scheduler count committed calendar hours within the current pay period when checking hour limits
- Exempt per-diem workers (pay_period_tracking = exempt) from period-based tracking
- Provide CLI commands to configure and inspect the pay period setting
- Maintain backward compatibility: default period type is `weekly`, which preserves current behavior

**Non-Goals:**
- Multiple pay period definitions (one per worker group) -- one definition covers the restaurant
- Payroll calculations, wage computation, or tax integration
- Historical pay period tracking (changing the period type does not rewrite history)
- Overtime rules tied to pay periods (overtime logic remains as-is; this change is about hour limits)
- Changes to the optimizer or perturbation strategies
- Display of pay period boundaries in schedule views (could be a follow-up)

## Decisions

### Pay period config is a single-row table

New `pay_period_config` table with columns `period_type TEXT` and `anchor_date TEXT`. At most one row. If no row exists, the system defaults to `weekly` with an arbitrary anchor (Monday of the current week), preserving existing behavior.

**Alternative considered:** Store period config as key-value pairs in the existing `scheduler_config` table. Rejected because pay period config is conceptually distinct from scheduler scoring weights, and having a dedicated table makes the schema clearer and avoids type confusion (scheduler_config values are REAL, but anchor_date is TEXT).

### Period types and date math

Four period types supported: `weekly`, `biweekly`, `semi-monthly`, `monthly`.

- **weekly**: 7-day periods starting from anchor. Equivalent to current behavior.
- **biweekly**: 14-day periods starting from anchor.
- **semi-monthly**: Two periods per month: 1st-15th and 16th-end. Anchor date is ignored (periods are calendar-fixed).
- **monthly**: Calendar month. Anchor date is ignored (periods align to 1st of month).

For weekly and biweekly, the anchor date defines the reference point. The period containing any date D is computed by: `days_since_anchor = D - anchor_date`, `period_number = floor(days_since_anchor / period_length)`, `period_start = anchor_date + period_number * period_length`.

New domain module `Domain/PayPeriod.hs` with:
- `PayPeriodType` data type (Weekly, Biweekly, SemiMonthly, Monthly)
- `PayPeriodConfig` record (type + anchor)
- `payPeriodBounds :: PayPeriodConfig -> Day -> (Day, Day)` returns (inclusive start, exclusive end) for the period containing the given day
- `defaultPayPeriodConfig :: PayPeriodConfig` returns Weekly with a fixed Monday anchor

**Alternative considered:** Represent all periods as fixed-day-count intervals. Rejected because semi-monthly and monthly periods have variable lengths tied to the calendar.

### Worker hour column reinterpretation

The existing `worker_hours.max_weekly_seconds` column is renamed to `max_period_seconds` in the schema (with backward-compatible migration: `ALTER TABLE worker_hours RENAME COLUMN max_weekly_seconds TO max_period_seconds`). The domain field `wcMaxWeeklyHours` in `WorkerContext` becomes `wcMaxPeriodHours`. The `worker set-hours` command value is interpreted as per-period hours.

When the period type is `weekly`, this is numerically identical to the old weekly limit. When biweekly, users set the biweekly limit (e.g., 80 hours for a full-time biweekly worker).

**Alternative considered:** Add a new column `max_period_seconds` alongside the old one and deprecate `max_weekly_seconds`. Rejected because maintaining two columns creates ambiguity about which one the scheduler reads. A clean rename is simpler since the default period type (weekly) preserves numeric compatibility.

### Scheduler integration: committed hours from calendar

The scheduler currently computes hours via `workerWeeklyHours w day sched` where `sched` is the draft being generated. To incorporate calendar hours:

1. Before scheduling begins, load the calendar for the current pay period's date range using `repoLoadCalendar`.
2. Pass the loaded calendar hours into the scheduler context as a new field `schCalendarHours :: Map WorkerId DiffTime` (pre-computed per-worker totals for the period).
3. Modify `workerWeeklyHours` (renamed to `workerPeriodHours`) to accept period bounds instead of computing ISO week bounds, and add the calendar hours to the draft hours.
4. For exempt workers (per-diem), set their calendar hours to 0 in the map, so they are tracked only within the draft as before.

The scheduler looks at most one pay period into the calendar. No historical lookback beyond the current period is needed.

**Alternative considered:** Have the scheduler query the database each time it checks hours. Rejected because `canAssignSlot` is called thousands of times per schedule generation. Pre-loading and pre-computing is essential for performance.

### Exempt workers bypass period tracking

Workers with `pay_period_tracking = exempt` (from Change 5) are excluded from calendar-hour loading. Their entries in `schCalendarHours` are set to 0 (or absent from the map). The hour limit check for exempt workers counts only hours in the draft schedule, preserving current behavior.

This means per-diem workers can still have a `max_period_seconds` value, but it functions as a per-schedule-generation limit rather than a calendar-aware period limit.

### CLI: config commands

New commands:
- `config set-pay-period <type> <anchor-date>` -- sets the pay period config. Type must be one of: weekly, biweekly, semi-monthly, monthly. Anchor date in YYYY-MM-DD format. For semi-monthly and monthly, anchor date is stored but not used in computation.
- `config show-pay-period` -- displays current pay period type, anchor date, and the date range of the current period.

These are added to the existing `config` command group in the CLI.

### Repo layer additions

New repository fields:
- `repoLoadPayPeriodConfig :: IO (Maybe PayPeriodConfig)` -- load config, Nothing if not set
- `repoSavePayPeriodConfig :: PayPeriodConfig -> IO ()` -- upsert the single config row

These sit alongside existing repo operations. The calendar loading (`repoLoadCalendar`) from Change 1 is reused to fetch committed hours for a pay period date range.

## Risks / Trade-offs

**[Risk] Column rename breaks existing databases** -- `ALTER TABLE ... RENAME COLUMN` requires SQLite 3.25.0+ (2018).
-> Mitigation: All modern SQLite versions support this. If needed, the migration can instead create a new table and copy data. The `CREATE TABLE IF NOT EXISTS` in Schema.hs will use the new column name; old databases get the ALTER on first run.

**[Risk] Pay period change mid-period creates confusion** -- If a manager changes from weekly to biweekly mid-week, committed hours from the old period type are suddenly reinterpreted under the new boundaries.
-> Mitigation: Document that pay period changes take effect for the next schedule generation. No retroactive recalculation. Managers should change pay period types at period boundaries.

**[Risk] Semi-monthly periods have unequal lengths** -- The 1st-15th period is 15 days; the 16th-end period is 13-16 days depending on the month. This means the same `max_period_seconds` represents different daily averages.
-> Mitigation: This matches real-world semi-monthly payroll. Restaurants already manage this. No special handling needed.

**[Risk] Calendar not populated for new restaurants** -- A new restaurant using biweekly periods but only generating one week at a time will have no calendar hours for the second week. The scheduler will allow the full period limit in week 1, then find the period nearly used up when generating week 2.
-> Mitigation: This is correct behavior -- the scheduler accurately reflects committed hours. Documentation should advise generating schedules for full pay periods or being aware of the running total.

**[Risk] Performance of calendar loading for long periods** -- Monthly periods could have many assignments to load.
-> Mitigation: For a restaurant with ~12 workers and 30 days, a monthly period has at most ~3000-5000 assignment rows. SQLite handles this in milliseconds. Pre-computing per-worker totals reduces the runtime impact to a single Map lookup per hour check.
