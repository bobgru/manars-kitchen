## Why

The scheduling system currently tracks worker hours on a weekly basis (`max_weekly_seconds` in `worker_hours`, `workerWeeklyHours` in the domain). Real restaurants use pay periods -- biweekly, semi-monthly, or monthly -- for hour tracking and labor cost management. With the employment status change (Change 5) introducing `pay_period_tracking` to distinguish standard vs exempt (per-diem) workers, this change adds the pay period concept itself so hour limits align with how restaurants actually manage labor.

## What Changes

- **New `pay_period_config` table** stores the restaurant-wide pay period definition: period type (weekly, biweekly, semi-monthly, monthly) and an anchor date (start of the first period). One row, one configuration for the whole restaurant.
- **Worker hour limits become per-period** instead of per-week. The existing `worker_hours.max_weekly_seconds` column is reinterpreted as `max_period_seconds` (or a new column replaces it). The `worker set-hours` CLI command reinterprets its value as per-period hours.
- **Scheduler counts committed calendar hours** within the current pay period. When evaluating whether a worker can take an assignment, the scheduler sums: (1) hours already committed in the calendar for the current pay period, plus (2) hours assigned so far in the draft being generated. Currently the scheduler only counts hours within the draft schedule.
- **Per-diem workers are exempt** from pay period hour tracking. Workers whose `pay_period_tracking` (from Change 5) is `exempt` are excluded from period-based hour counting and use only the draft-schedule hours (preserving current behavior).
- **New CLI commands** for pay period configuration: `config set-pay-period <type> <anchor-date>` and `config show-pay-period`. Worker hour limits displayed as per-period in relevant output.

## Capabilities

### New Capabilities
- `pay-period-config`: Restaurant-wide pay period definition (type and anchor date), storage, CLI commands for configuration, and the domain logic for computing which pay period a given date falls in.
- `pay-period-scheduling`: Scheduler integration for per-period hour tracking -- loading committed calendar hours for the current pay period, combining them with draft hours, and enforcing per-period limits. Includes exemption logic for per-diem workers.

### Modified Capabilities
(none -- no existing spec-level requirements change; the hour limit reinterpretation is a new capability, not a modification of an existing spec)

## Impact

- **Database schema**: New `pay_period_config` table. The `worker_hours` table column semantics shift from weekly to per-period (backward compatible: weekly is the default period type).
- **Domain layer**: New `PayPeriod` type and date-math functions in `Domain/` (or a new `Domain/PayPeriod.hs`). Changes to `WorkerContext` or a new context type to carry per-period hour data.
- **Scheduler**: `Domain/Scheduler.hs` gains awareness of committed calendar hours. `canAssignSlot` and scoring functions that check `wouldBeOvertime` / `workerWeeklyHours` need to account for calendar-committed hours in the pay period.
- **Repository layer**: New repo functions to load/save pay period config and to query calendar hours for a date range (may reuse `repoLoadCalendar` from Change 1).
- **Service layer**: New or extended config service for pay period CRUD.
- **CLI**: New `config set-pay-period` and `config show-pay-period` commands. `worker set-hours` output labels change from "weekly" to "per-period".
- **Dependencies**: Depends on calendar-foundation (Change 1) for calendar queries and employment-status (Change 5) for `pay_period_tracking` field.
