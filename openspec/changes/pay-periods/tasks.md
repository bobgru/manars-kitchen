## 1. Database Schema

- [ ] 1.1 Add `pay_period_config` table to `Repo/Schema.hs` with columns `period_type TEXT` and `anchor_date TEXT`
- [ ] 1.2 Rename `worker_hours.max_weekly_seconds` column to `max_period_seconds` in `Repo/Schema.hs` (new databases use new name; existing databases get ALTER on first run)

## 2. Domain Types

- [ ] 2.1 Create `Domain/PayPeriod.hs` with `PayPeriodType` data type (Weekly, Biweekly, SemiMonthly, Monthly) and `PayPeriodConfig` record (type + anchor date)
- [ ] 2.2 Implement `payPeriodBounds :: PayPeriodConfig -> Day -> (Day, Day)` for weekly and biweekly (anchor-relative modular arithmetic)
- [ ] 2.3 Implement `payPeriodBounds` for semi-monthly (1st-15th, 16th-end) and monthly (1st to 1st of next month)
- [ ] 2.4 Implement `defaultPayPeriodConfig` returning Weekly with a fixed Monday anchor
- [ ] 2.5 Add `parsePayPeriodType :: String -> Maybe PayPeriodType` and `showPayPeriodType :: PayPeriodType -> String` for CLI/storage conversions

## 3. Worker Context Update

- [ ] 3.1 Rename `wcMaxWeeklyHours` to `wcMaxPeriodHours` in `Domain/Worker.hs` `WorkerContext` and update all references
- [ ] 3.2 Rename `workerWeeklyHours` to `workerPeriodHours` taking period start/end instead of computing ISO week, update callers
- [ ] 3.3 Update `wouldBeOvertime` to accept period bounds and calendar hours, using `workerPeriodHours` plus calendar hours for standard workers
- [ ] 3.4 Update `workerMaxHours` to reflect the per-period naming

## 4. Repository Layer

- [ ] 4.1 Add `repoLoadPayPeriodConfig :: IO (Maybe PayPeriodConfig)` and `repoSavePayPeriodConfig :: PayPeriodConfig -> IO ()` to `Repo/Types.hs`
- [ ] 4.2 Implement `sqlLoadPayPeriodConfig` and `sqlSavePayPeriodConfig` in `Repo/SQLite.hs`
- [ ] 4.3 Wire pay period config functions into the `Repository` record constructor
- [ ] 4.4 Update `sqlLoadWorkerHours` and `sqlSaveWorkerHours` for the renamed column (`max_period_seconds`)

## 5. Scheduler Integration

- [ ] 5.1 Add `schCalendarHours :: Map WorkerId DiffTime` field to `SchedulerContext` in `Domain/Scheduler.hs`
- [ ] 5.2 Add `schPeriodBounds :: (Day, Day)` field to `SchedulerContext` for the current pay period boundaries
- [ ] 5.3 Update `canAssignSlot` to use period bounds and calendar hours when checking `wouldBeOvertime`
- [ ] 5.4 Update `scoreShiftWorker` capacity score to use period hours (calendar + draft) for standard workers
- [ ] 5.5 Update `scoreSlotWorker` capacity score to use period hours (calendar + draft) for standard workers
- [ ] 5.6 Update `computeOvertime` to use period bounds instead of ISO week boundaries
- [ ] 5.7 Add logic to set calendar hours to 0 for exempt workers (per-diem) when building the scheduler context

## 6. Service Layer

- [ ] 6.1 Add `loadPayPeriodConfig` and `savePayPeriodConfig` to `Service/Config.hs` (or a new `Service/PayPeriod.hs`)
- [ ] 6.2 Create helper to pre-compute `Map WorkerId DiffTime` from calendar assignments for a date range, excluding exempt workers
- [ ] 6.3 Integrate calendar hour loading into the schedule generation flow (where `SchedulerContext` is built before calling `buildSchedule`)

## 7. CLI Commands

- [ ] 7.1 Add `config set-pay-period <type> <anchor-date>` command to `CLI/Commands.hs` parser
- [ ] 7.2 Implement `config set-pay-period` handler with validation (type and date format)
- [ ] 7.3 Add `config show-pay-period` command to `CLI/Commands.hs` parser
- [ ] 7.4 Implement `config show-pay-period` handler displaying type, anchor, and current period boundaries
- [ ] 7.5 Update `worker set-hours` output labels from "weekly" to "per-period"
- [ ] 7.6 Add pay period commands to help text

## 8. Testing

- [ ] 8.1 Add unit tests for `payPeriodBounds` covering all four period types and edge cases (month boundaries, leap year, anchor alignment)
- [ ] 8.2 Add unit tests for `workerPeriodHours` with period bounds instead of ISO week
- [ ] 8.3 Add unit tests for `wouldBeOvertime` with calendar hours (standard worker includes calendar, exempt worker excludes)
- [ ] 8.4 Add integration test: scheduler respects period limits when calendar hours are pre-loaded
- [ ] 8.5 Add tests for pay period config save/load round-trip (including default when no config exists)
- [ ] 8.6 Add tests for exempt worker bypass (per-diem workers tracked only within draft)
