## 1. Database Schema

- [x] 1.1 Add `worker_employment` table to `Repo/Schema.hs` with columns: worker_id (PK), overtime_model (TEXT, CHECK IN eligible/manual-only/exempt, DEFAULT eligible), pay_period_tracking (TEXT, CHECK IN standard/exempt, DEFAULT standard), is_temp (BOOLEAN, DEFAULT 0)

## 2. Domain Types

- [x] 2.1 Add `OvertimeModel` data type (`OTEligible | OTManualOnly | OTExempt`) with Eq, Ord, Show, Read instances to `Domain/Worker.hs`
- [x] 2.2 Add `PayPeriodTracking` data type (`PPStandard | PPExempt`) with Eq, Ord, Show, Read instances to `Domain/Worker.hs`
- [x] 2.3 Add three new fields to `WorkerContext`: `wcOvertimeModel :: Map WorkerId OvertimeModel`, `wcPayPeriodTracking :: Map WorkerId PayPeriodTracking`, `wcIsTemp :: Set WorkerId`
- [x] 2.4 Update `emptyWorkerContext` to initialize the three new fields (empty Map/Set)
- [x] 2.5 Add query functions: `workerOvertimeModel` (returns OTEligible default), `workerPayPeriodTracking` (returns PPStandard default), `workerIsTemp`

## 3. Repository Layer

- [x] 3.1 Add employment CRUD fields to `Repository` record in `Repo/Types.hs`: `repoLoadEmployment`, `repoSaveEmployment`
- [x] 3.2 Implement `sqlLoadEmployment` in `Repo/SQLite.hs` — load all rows from worker_employment into maps
- [x] 3.3 Implement `sqlSaveEmployment` in `Repo/SQLite.hs` — upsert a single worker's employment record
- [x] 3.4 Wire new SQL functions into the `Repository` record constructor
- [x] 3.5 Extend `loadWorkerCtx` (or its SQLite implementation) to also load employment data and populate the three new WorkerContext fields

## 4. Domain Logic Updates

- [x] 4.1 Update `wouldBeOvertime` to return False for workers with `PPExempt` pay period tracking (no hour limit enforced)
- [x] 4.2 Replace `workerOptedInOvertime` usage with overtime model check: `OTEligible` means eligible for auto-assignment, `OTManualOnly` means never auto-assigned, `OTExempt` means no overtime concept
- [x] 4.3 Update `tryAssignOvertimeHours` to use the new overtime model instead of wcOvertimeOptIn

## 5. Scheduler Integration

- [x] 5.1 Update `canAssignSlot` weeklyOk clause to respect overtime model: OTManualOnly workers never get auto-overtime, OTExempt workers skip overtime check entirely
- [x] 5.2 Update `canAssignSlot` to skip weekly hour limit check for workers with PPExempt pay period tracking
- [x] 5.3 Verify Phase 2 (`retryUnfilledSlotsP`) correctly filters out manual-only workers through the updated `canAssignSlot` logic

## 6. Service Layer

- [x] 6.1 Add `setOvertimeModel` function to `Service/Worker.hs` — saves overtime model for a worker
- [x] 6.2 Add `setPayPeriodTracking` function to `Service/Worker.hs` — saves pay period tracking for a worker
- [x] 6.3 Add `setTempFlag` function to `Service/Worker.hs` — saves temp flag for a worker
- [x] 6.4 Add `setEmploymentStatus` function to `Service/Worker.hs` — applies a preset (salaried/full-time/part-time/per-diem) by setting all decomposed properties and hour limit
- [x] 6.5 Update `setOvertimeOptIn` to interact with the new model: for non-salaried workers, set overtime_model; for salaried workers, warn and no-op

## 7. CLI Commands

- [x] 7.1 Add `WorkerSetStatus Int String` command variant to `CLI/Commands.hs` parser for `worker set-status <w> salaried|full-time|part-time|per-diem`
- [x] 7.2 Add `WorkerSetOvertimeModel Int String` command variant to parser for `worker set-overtime-model <w> eligible|manual-only|exempt`
- [x] 7.3 Add `WorkerSetPayTracking Int String` command variant to parser for `worker set-pay-tracking <w> standard|exempt`
- [x] 7.4 Add `WorkerSetTemp Int Bool` command variant to parser for `worker set-temp <w> on|off`
- [x] 7.5 Implement handlers for the four new commands in `CLI/App.hs`, calling the corresponding service functions
- [x] 7.6 Update the `WorkerSetOvertime` handler to check overtime model and warn for salaried workers

## 8. CLI Display

- [x] 8.1 Update `worker info` display in `CLI/Display.hs` to show overtime model, pay period tracking, and temp flag for each worker

## 9. Testing

- [x] 9.1 Add unit tests for `wouldBeOvertime` with PPExempt workers (should return False regardless of hours)
- [x] 9.2 Add unit tests for overtime model query functions (OTEligible, OTManualOnly, OTExempt defaults and explicit values)
- [x] 9.3 Add unit tests for `tryAssignOvertimeHours` with each overtime model variant
- [x] 9.4 Add scheduler integration test: Phase 2 does not auto-assign overtime to manual-only workers
- [x] 9.5 Add scheduler integration test: exempt pay period tracking workers are assignable beyond weekly hour limit
- [x] 9.6 Add test for convenience presets: verify `setEmploymentStatus` sets correct decomposed properties for each preset
