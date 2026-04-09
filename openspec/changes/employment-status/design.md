## Context

The system currently models worker scheduling constraints through two mechanisms in `Domain/Worker.hs`:

- `wcMaxWeeklyHours :: Map WorkerId DiffTime` — optional weekly hour cap per worker
- `wcOvertimeOptIn :: Set WorkerId` — binary overtime availability flag

These are stored in two database tables (`worker_hours` and `worker_overtime_optin`) and loaded into `WorkerContext` at startup. The scheduler uses `wouldBeOvertime` to check hour limits and `workerOptedInOvertime` to decide if overtime is allowed in Phase 2.

This flat model cannot represent the real scheduling implications of different employment types. A salaried manager should never have overtime auto-assigned (the scheduler does not decide to give the manager extra hours — the manager decides). A per-diem worker has no meaningful weekly hour limit. The current boolean overtime toggle conflates "eligible for auto-assignment" with "allowed to work overtime at all."

The repository uses a record-of-functions pattern (`Repo/Types.hs`), making it straightforward to add new operations. The `WorkerContext` is loaded once and threaded through the scheduler — extending it with new fields has minimal performance impact.

## Goals / Non-Goals

**Goals:**
- Introduce decomposed employment properties (overtime model, pay period tracking, temp flag) that the scheduler respects
- Provide a convenience command (`worker set-status`) for common employment presets alongside direct property commands
- Maintain backward compatibility: existing `worker set-hours` and `worker set-overtime` commands continue to work, with `set-overtime` reinterpreted through the new model
- Keep the `WorkerContext` as the single source of truth for the scheduler — no separate "employment context"

**Non-Goals:**
- Pay calculation or payroll integration — this is scheduling-only
- Per-diem rate tracking or billing
- Employment history or status change auditing (future work)
- Changes to the scheduler algorithm beyond Phase 2 filtering and hour limit exemption
- Multi-period hour tracking (e.g., bi-weekly, monthly) — only weekly limits exist today

## Decisions

### Employment status decomposes into orthogonal properties, not an enum

New fields on `WorkerContext`:
- `wcOvertimeModel :: Map WorkerId OvertimeModel` where `data OvertimeModel = OTEligible | OTManualOnly | OTExempt`
- `wcPayPeriodTracking :: Map WorkerId PayPeriodTracking` where `data PayPeriodTracking = PPStandard | PPExempt`
- `wcIsTemp :: Set WorkerId`

**Alternative considered:** A single `EmploymentStatus` enum with constructors `Salaried | FullTime | PartTime | PerDiem`. Rejected because the enum conflates independent properties. A salaried worker with custom overtime rules would require a new enum variant. The decomposed model allows combinations the enum cannot express, and each property maps directly to one scheduler behavior.

### Convenience presets map to decomposed properties

`worker set-status salaried` sets: overtime_model=manual-only, pay_period_tracking=standard, hour_limit=40h (via existing set-hours). `worker set-status full-time`: overtime_model=eligible, pay_period_tracking=standard, hour_limit=40h. `worker set-status part-time`: overtime_model=eligible, pay_period_tracking=standard, hour_limit unchanged. `worker set-status per-diem`: overtime_model=exempt, pay_period_tracking=exempt, removes hour_limit.

The presets are a CLI convenience — the domain layer only knows about the decomposed properties.

### Existing wcOvertimeOptIn is replaced, not extended

The current `wcOvertimeOptIn :: Set WorkerId` is replaced by `wcOvertimeModel`. The migration path:
- Workers currently in `wcOvertimeOptIn` get `OTEligible`
- Workers not in `wcOvertimeOptIn` with no employment record retain default behavior (treated as `OTEligible` but without opt-in — the existing logic)
- The `worker_overtime_optin` table remains in the schema for backward compatibility but `loadWorkerCtx` reads from `worker_employment` when present

`worker set-overtime on` for a non-salaried worker sets overtime_model to `OTEligible`. `worker set-overtime off` sets it back to the default (no entry = not opted in, same as today). For a salaried worker, `set-overtime` is a no-op with a warning message — salaried overtime is always manual-only.

**Alternative considered:** Keep `wcOvertimeOptIn` alongside the new model. Rejected because having two sources of truth for overtime behavior creates ambiguity in the scheduler. A single `wcOvertimeModel` field is cleaner.

### New database table alongside existing tables

A new `worker_employment` table with columns:
- `worker_id INTEGER PRIMARY KEY`
- `overtime_model TEXT NOT NULL DEFAULT 'eligible' CHECK (overtime_model IN ('eligible', 'manual-only', 'exempt'))`
- `pay_period_tracking TEXT NOT NULL DEFAULT 'standard' CHECK (pay_period_tracking IN ('standard', 'exempt'))`
- `is_temp BOOLEAN NOT NULL DEFAULT 0`

The existing `worker_hours` and `worker_overtime_optin` tables are not removed. `loadWorkerCtx` reads from all tables and synthesizes the `WorkerContext`. When a worker has an entry in `worker_employment`, the overtime_model from that table takes precedence over the `worker_overtime_optin` table.

**Alternative considered:** Add columns to `worker_hours`. Rejected because `worker_hours` has a single-column PK and adding unrelated columns violates cohesion. A dedicated table is clearer.

### Scheduler changes are minimal and targeted

Phase 2 (`retryUnfilledSlotsP`): before calling `pickSlotWorkerP`, the candidate filtering in `canAssignSlot` already gates on overtime. The change is in `canAssignSlot`'s `weeklyOk` clause: instead of checking `workerOptedInOvertime`, check the overtime model:
- `OTEligible` + `allowOT=True` → overtime allowed (auto-assign OK)
- `OTManualOnly` → overtime never allowed in auto-scheduling (skipped in Phase 2)
- `OTExempt` → overtime concept doesn't apply; weekly limit doesn't apply either

For `wouldBeOvertime`: workers with `PPExempt` pay period tracking always return `False` (no hour limit to exceed).

### WorkerContext fields default to backward-compatible values

Workers without an entry in `worker_employment` get:
- `OTEligible` overtime model (but only auto-assigned if they were in `wcOvertimeOptIn`)
- `PPStandard` pay period tracking
- `is_temp = False`

This means the migration is zero-effort: existing data continues to work identically.

## Risks / Trade-offs

**[Risk] Two overtime mechanisms during transition** — Both `worker_overtime_optin` and `worker_employment.overtime_model` exist. A worker could have conflicting settings.
--> Mitigation: `loadWorkerCtx` implements a clear precedence: if `worker_employment` row exists, its `overtime_model` is authoritative. The old `worker_overtime_optin` is only consulted for workers without an employment record. `worker set-overtime` updates both tables to keep them in sync.

**[Risk] Convenience presets override individual settings** — Running `worker set-status salaried` overwrites a carefully tuned overtime_model.
--> Mitigation: The CLI warns when overwriting non-default employment properties. The individual property commands (`set-overtime-model`, `set-pay-tracking`) exist for fine-grained control.

**[Trade-off] No employment history** — Changing a worker's status has no audit trail beyond the general audit log.
--> Acceptable for now. The audit log captures all CLI commands. Dedicated employment history tracking is deferred to future work.

**[Trade-off] Presets set hour_limit for salaried/full-time but not part-time** — Part-time hours vary too much for a default. The manager must still run `worker set-hours` after `worker set-status part-time`.
--> Acceptable. The CLI output from `set-status part-time` reminds the user to set hours.
