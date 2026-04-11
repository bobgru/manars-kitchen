## 1. Database Schema

- [x] 1.1 Add `pay_period_config` table to `Repo/Schema.hs` with columns `period_type TEXT` and `anchor_date TEXT`
- [x] 1.2 Rename `worker_hours.max_weekly_seconds` column to `max_period_seconds` in `Repo/Schema.hs` (new databases use new name; existing databases get ALTER on first run)

## 2. Domain Types

- [x] 2.1 Create `Domain/PayPeriod.hs` with `PayPeriodType` data type (Weekly, Biweekly, SemiMonthly, Monthly) and `PayPeriodConfig` record (type + anchor date)
- [x] 2.2 Implement `payPeriodBounds :: PayPeriodConfig -> Day -> (Day, Day)` for weekly and biweekly (anchor-relative modular arithmetic)
- [x] 2.3 Implement `payPeriodBounds` for semi-monthly (1st-15th, 16th-end) and monthly (1st to 1st of next month)
- [x] 2.4 Implement `defaultPayPeriodConfig` returning Weekly with a fixed Monday anchor
- [x] 2.5 Add `parsePayPeriodType :: String -> Maybe PayPeriodType` and `showPayPeriodType :: PayPeriodType -> String` for CLI/storage conversions

## 3. Worker Context Update

- [x] 3.1 Rename `wcMaxWeeklyHours` to `wcMaxPeriodHours` in `Domain/Worker.hs` `WorkerContext` and update all references
- [x] 3.2 Rename `workerWeeklyHours` to `workerPeriodHours` taking period start/end instead of computing ISO week, update callers
- [x] 3.3 Update `wouldBeOvertime` to accept period bounds and calendar hours, using `workerPeriodHours` plus calendar hours for standard workers
- [x] 3.4 Update `workerMaxHours` to reflect the per-period naming

## 4. Repository Layer

- [x] 4.1 Add `repoLoadPayPeriodConfig :: IO (Maybe PayPeriodConfig)` and `repoSavePayPeriodConfig :: PayPeriodConfig -> IO ()` to `Repo/Types.hs`
- [x] 4.2 Implement `sqlLoadPayPeriodConfig` and `sqlSavePayPeriodConfig` in `Repo/SQLite.hs`
- [x] 4.3 Wire pay period config functions into the `Repository` record constructor
- [x] 4.4 Update `sqlLoadWorkerHours` and `sqlSaveWorkerHours` for the renamed column (`max_period_seconds`)

## 5. Scheduler Integration

- [x] 5.1 Add `schCalendarHours :: Map WorkerId DiffTime` field to `SchedulerContext` in `Domain/Scheduler.hs`
- [x] 5.2 Add `schPeriodBounds :: (Day, Day)` field to `SchedulerContext` for the current pay period boundaries
- [x] 5.3 Update `canAssignSlot` to use period bounds and calendar hours when checking `wouldBeOvertime`
- [x] 5.4 Update `scoreShiftWorker` capacity score to use period hours (calendar + draft) for standard workers
- [x] 5.5 Update `scoreSlotWorker` capacity score to use period hours (calendar + draft) for standard workers
- [x] 5.6 Update `computeOvertime` to use period bounds instead of ISO week boundaries
- [x] 5.7 Add logic to set calendar hours to 0 for exempt workers (per-diem) when building the scheduler context

## 6. Service Layer

- [x] 6.1 Add `loadPayPeriodConfig` and `savePayPeriodConfig` to `Service/Config.hs` (or a new `Service/PayPeriod.hs`)
- [x] 6.2 Create helper to pre-compute `Map WorkerId DiffTime` from calendar assignments for a date range, excluding exempt workers
- [x] 6.3 Integrate calendar hour loading into the schedule generation flow (where `SchedulerContext` is built before calling `buildSchedule`)

## 7. CLI Commands

- [x] 7.1 Add `config set-pay-period <type> <anchor-date>` command to `CLI/Commands.hs` parser
- [x] 7.2 Implement `config set-pay-period` handler with validation (type and date format)
- [x] 7.3 Add `config show-pay-period` command to `CLI/Commands.hs` parser
- [x] 7.4 Implement `config show-pay-period` handler displaying type, anchor, and current period boundaries
- [x] 7.5 Update `worker set-hours` output labels from "weekly" to "per-period"
- [x] 7.6 Add pay period commands to help text

## 8. Testing

- [x] 8.1 Add unit tests for `payPeriodBounds` covering all four period types and edge cases (month boundaries, leap year, anchor alignment)
- [x] 8.2 Add unit tests for `workerPeriodHours` with period bounds instead of ISO week
- [x] 8.3 Add unit tests for `wouldBeOvertime` with calendar hours (standard worker includes calendar, exempt worker excludes)
- [x] 8.4 Add integration test: scheduler respects period limits when calendar hours are pre-loaded
- [x] 8.5 Add tests for pay period config save/load round-trip (including default when no config exists)
- [x] 8.6 Add tests for exempt worker bypass (per-diem workers tracked only within draft)
