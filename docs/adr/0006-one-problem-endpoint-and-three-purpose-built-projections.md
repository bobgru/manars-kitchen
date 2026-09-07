# One problem endpoint, three purpose-built projections

ADR 0004 settled *what* the problem view is. This records what building it settled: how a
client gets a problem set, what a `Problem` is in the type system, and which compromises
are derivable today. Read 0004 first — this refines it and, in one place, corrects it.

`GET /api/problems?from=&to=` returns a flat list, each problem declaring an optional
worker, an optional station and a date-or-slot scope. The three visualizations are
client-side filters over one fetch. `GET /api/horizons` separately returns today, the
current pay period and the next as `{key, label, from, to}`, and the browser fetches
problems once over the union of those ranges — today sits inside the current period, so
`[currentPeriodStart, nextPeriodEnd]` covers all three. Switching horizon costs no
request, and the marks on the horizon control cannot disagree with the view they select.

`Problem` is a three-constructor sum, not a record with a kind field, with `problemWorker`,
`problemStation`, `problemScope` and `problemSeverity` as total functions over it.
`PViolation` wraps the existing `DraftViolation` rather than re-modelling it. Severity
orders `Violation > Understaffing > Compromise`.

## Considered Options

**Three endpoints, one per projection**, was rejected because it is the mechanism by which
the three views would stop agreeing. ADR 0004's whole claim is that they are projections of
one set; three queries make that a promise rather than a fact.

**`?horizon=today|current-period|next-period` instead of `from`/`to`** was rejected as a
second way to ask the same question. The cost is one extra read for the ranges, and the
benefit is that `payPeriodBounds` stays the single source of truth in Haskell with no
date arithmetic duplicated in TypeScript — `PayPeriodType` is configurable, so "current
period" is a range only the server can compute.

**Reusing `ScheduleGrid` for the three visualizations** was rejected even though all three
are day-columned tables. The grid renders assignments as chips; these render an aggregate
per cell — most-severe kind plus earliest affected date. Sharing would mean handing cell
rendering back to every caller through a render-prop, which is the "thin table shell with
the interesting logic outside the module" outcome that the layout-preset decision in
ADR 0005 already rejected once. The station view also needs zone row-grouping, which the
grid has no concept of. The `calendar-*` CSS is shared instead, so the three read as one
system without the coupling. A consequence: `ScheduleGrid`'s deferred `workers-days` and
`stations-days` layouts are **not** delivered as a side effect of this work.

**Understaffing outranking violations** is arguable and was not chosen. Understaffing means
a station cannot run, which is the more immediate operational fact; a violation may be a
labour-rule breach, which is always actionable and sometimes legally material. What makes
the choice low-stakes is that severity decides only which kind a *cell* announces — every
cell also shows its earliest affected date, and clicking it lists everything in it, so
nothing is unreachable.

**Shift preference as a compromise** was rejected because **the scheduler never reads
`wcShiftPrefs`**. It is stored, set, displayed and exported, and no scheduling code
consults it — `scoreSlotWorker` does not mention it. Reporting it would raise a compromise
against nearly every assignment of every worker who has a shift preference, describing a
missing scheduler feature rather than a trade-off anyone made. `CONTEXT.md`'s Compromise
entry promised it and has been corrected.

**Deriving compromises from "the penalty components" of `scoreSlotWorker`**, as ADR 0004
puts it, does not work as written: only two of the seven components can go negative
(`capacityScore` over limit, `varietyScore` on a repeat). The other five are bonuses, so
what marks a compromise there is a bonus that is *absent* — `prefScore == 0` means the
station is not in the worker's list at all. So the first cut derives three:

- **Authorised overtime** — `exceedsPermittedHours` false while `wouldBeOvertime` true,
  which is exactly the definition of permitted overtime.
- **Station not preferred** — `stationPreferenceRank` returns `Nothing` *and* the worker
  has a non-empty preference list. A worker with no preferences was not disappointed.
- **Variety repeat** — a `prefersVariety` worker on a station they held inside the same
  three-day window `varietyScore` uses.

**Pairing, multi-station and cross-training bonuses** are not compromises. Nobody stated a
preference against working without their preferred coworker on a given hour, and reporting
absent bonuses of that kind would bury the three above.

## Consequences

Computing problems needs the same `SchedulerContext` assembly that `Service.Draft` and
`Service.DraftValidation` each already build, so it is extracted rather than copied a
third time. The two existing copies genuinely differ — `generateDraft` fills `schSlots`
and `schClosedSlots`, `validateDraft` leaves them empty and sets `schPrevWeekendWorkers`
from a look-back — so the extraction parameterises those rather than pretending they are
the same.

**Extracting it exposed a third instance of the bug ADR 0005 fixed.**
`validateDraft` set `schPeriodBounds` to the *draft's own date range* and
`schCalendarHours` to empty, where `generateDraft` uses `payPeriodBounds` and real
calendar hours. `CONTEXT.md` defines the pay period as the interval hour limits are
measured over, so the validator was measuring against the wrong window — too permissive
when the pay period is longer than the draft, too strict when shorter — and ignoring hours
already committed to the calendar. Fixed with the extraction, because a shared loader has
to pick one answer.

The problem set is about the **calendar**, not about drafts. That is what ADR 0004's
virtual default draft means; drafts have their own page, and `computeProblems` never reads
the `drafts` table.

Selecting a problem highlights its worker row, station row and hour cell across all three
panels, captioned in words — "Showing: Ana · grill · Thu 10-08". Three simultaneously
outlined cells with no caption is a puzzle, and an outline colour is not something every
reader can distinguish.
