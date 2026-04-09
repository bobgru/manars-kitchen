## Why

The scheduling system currently models all workers identically: each has a weekly hour limit and an overtime on/off toggle. Real restaurants employ salaried managers, full-time cooks, part-time prep staff, and per-diem workers — each with fundamentally different scheduling rules around overtime eligibility, hour tracking, and pay period handling. Without this distinction, the scheduler cannot correctly handle salaried workers (who should never be auto-assigned overtime) or per-diem workers (who have no meaningful hour limit). This is Change 5 of 7 in the planned system evolution.

## What Changes

- **Employment status as decomposed properties** rather than a single enum. Four orthogonal axes:
  - `overtime_model`: `eligible` (scheduler auto-assigns OT), `manual-only` (manager must explicitly accept; salaried), or `exempt` (concept doesn't apply; per-diem)
  - `pay_period_tracking`: `standard` (hours tracked against weekly limit) or `exempt` (no hour limit enforced; per-diem)
  - `is_temp`: boolean flag, informational only, no calculation impact
  - Hour limit (`worker set-hours`) remains as-is — the convenience presets set it to typical values
- **Convenience command**: `worker set-status <w> salaried|full-time|part-time|per-diem` sets all decomposed properties at once using standard presets
- **Direct property commands**: `worker set-overtime-model`, `worker set-pay-tracking`, `worker set-temp` for fine-grained control
- **Scheduler Phase 2 change**: overtime retry loop skips workers with `manual-only` overtime model — the scheduler never auto-assigns overtime to salaried workers
- **Hour limit exemption**: workers with `exempt` pay period tracking have no weekly hour limit enforced by the scheduler
- **Reinterpretation of `worker set-overtime on/off`**: for hourly workers, sets overtime_model to `eligible`/back to default; for salaried workers, overtime is always `manual-only` regardless of this setting
- **Display**: `worker info` shows employment status properties

## Capabilities

### New Capabilities
- `employment-status`: Worker employment classification with decomposed properties (overtime model, pay period tracking, temp flag) that influence scheduler behavior — specifically overtime eligibility and hour limit enforcement

### Modified Capabilities

## Impact

- **Database schema**: New `worker_employment` table in `Repo/Schema.hs` (worker_id PK, overtime_model, pay_period_tracking, is_temp)
- **Domain types**: New `OvertimeModel` and `PayPeriodTracking` algebraic types in `Domain/Worker.hs`; `WorkerContext` gains three new fields
- **Domain logic**: `wouldBeOvertime` respects pay period exemption; `workerOptedInOvertime` replaced by richer overtime model queries
- **Scheduler**: `Domain/Scheduler.hs` Phase 2 filters by overtime model; `canAssignSlot` respects exempt tracking
- **Repository**: `Repo/Types.hs` and `Repo/SQLite.hs` gain employment CRUD; `loadWorkerCtx`/`saveWorkerCtx` extended
- **Service**: `Service/Worker.hs` gains employment status functions
- **CLI**: New commands in `CLI/Commands.hs`; enhanced `worker info` display in `CLI/Display.hs`
