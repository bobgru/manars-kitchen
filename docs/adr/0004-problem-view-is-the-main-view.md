# The problem view is the main view, and the calendar is a secondary read

The application's purpose is incremental scheduling: most days, an admin is not building
a schedule but reacting to something that broke one. So `/` is a visualization of
**problems**, not a summary of entities and not the calendar. The calendar is reachable
from the sidebar when someone wants to read it, and carries no problem annotation of its
own — the problem view already is that annotation.

Problems are shown three ways at once, one per entity that makes up an assignment:
**workers**, **stations** and **slots**. These are three projections of one problem set,
not three independent computations. Each problem declares which entities it touches — an
optional worker, an optional station, and a date or slot scope — so a projection is a
filter and "highlight everything related to this problem" is a lookup. This matters
because problems do not all have all three: understaffing against `stationMinStaff` is a
station×slot fact with no worker at all, and a worker over their pay-period hour limit is
a worker fact spanning many stations and many days. A flat model would have to lie about
one or the other.

A **Problem** is one of three things, and the distinction is what the view encodes:

- **Violation** — an existing assignment breaks a hard rule. Already computed by
  `Service.DraftValidation.validateAssignment`, already named `DraftViolation`.
- **Compromise** — an assignment is legal but ignores a stated preference. Derived from
  the penalty components of `Domain.Scheduler.scoreSlotWorker` (over-limit, variety
  repeat, and so on), *not* from a threshold on the total score.
- **Understaffing** — a station has fewer assignments than `stationMinStaff` for a slot.
  Where `stationMinStaff` is zero, an unfilled slot is not a problem and the cell reads
  as empty.

Each cell aggregates to its most severe problem and additionally shows the **earliest
affected date**, because the question an admin is asking is "must I act today", which a
count of six does not answer.

The horizon is **today / current pay period / next pay period**, derived from
`Domain.PayPeriod.payPeriodBounds`, presented as a three-segment control that both marks
where problems exist and selects which one the visualizations show.

## Considered Options

**A real default-draft row** mirroring the calendar, so that violations become computable
by reusing draft machinery, was the original idea and was rejected because the draft
lifecycle makes no sense applied to it: committing it would mean committing the calendar
onto itself, `DraftInfo` requires a concrete finite `diDateFrom`/`diDateTo`,
`repoCheckDraftOverlap` would make every real draft collide with it, and the freeze line
would render the part of it covering the past permanently unmodifiable. Instead the
validation core is generalised to take a `Schedule` plus a date range, and the calendar
slice is fed through it — the default draft is **virtual**.

**Persisting calendar violations** in their own table, recomputed on write, was rejected
for the reason that motivates this whole design: an approved absence invalidates calendar
assignments *without changing the calendar*, so a write-triggered cache misses precisely
the event that matters. This is the same trap as the staleness gate in
`pruneDraftViolations`, which only fires on a calendar commit.

**A flat `Violation` type with a severity field** was rejected because it is what lets a
station's understaffing and a worker's overtime land in one list pretending to be the
same kind of thing.

**Hardcoded today / this week / this month** buckets were rejected because
`PayPeriodType` is configurable (`Weekly | Biweekly | SemiMonthly | Monthly`, default
`Weekly`): a week is not an accounting unit for a monthly-paid restaurant, and hour
limits are measured over `schPeriodBounds`. Aggregating hour problems over a window that
is not the pay period reports against a rule nobody is bound by. The cost accepted is
dynamic labels — "current period" renders as a date range, not a word.

**Counting absences only once approved** was rejected because it inverts cause and
effect: the worker being sick is the problem, the admin's approval is bookkeeping. A
worker can already submit their own request from a mobile client
(`handleRequestAbsence` is `requireSelfOrAdmin`), but it lands `Pending` and
`Domain.Absence.isWorkerAvailable` counts only `Approved`, so today a sick call has no
effect until an admin acts. An **auto-approving absence type** fixes that — the same
per-type-flag shape as the existing `atYearlyLimit`.

**A floor plan with stored coordinates** for the station view was deferred in favour of a
**zone label**, which buys the spatial grouping that makes a hot area visible as a block
without a coordinate migration, a background asset, or a placement editor. Stations with
no zone group under "Unassigned" rather than needing the special sidebar the sketch
anticipated.

**Annotating the sidebar's Calendar link** when the calendar has problems was rejected as
redundant: the horizon control already carries that mark, and it is where someone
looking for it will be looking.

## Consequences

`Service.DraftValidation`'s private `validateDraft` has to be generalised from
`DraftInfo` to a `Schedule` plus a `(Day, Day)` range. Today's split
(`computeDraftViolations` / `pruneDraftViolations` / `isDraftStale`) already isolated
that body, so this is close to mechanical.

**Compromise has no implementation.** The soft score exists only inside the optimizer's
hill climbing and is never surfaced to any client; deriving per-assignment compromises
from its penalty components is new work, and each one needs a sentence a detail pane can
show. A score is not an explanation.

**Auto-approving absence types mean a worker can grant themselves an absence** by
choosing that type, since request is `requireSelfOrAdmin`. For sick leave this is
intended and matches how restaurants work, but it is a real authorization change and not
a side effect to discover later.

Stations need a nullable zone column, and `Station` currently has no such field —
`{stationName, stationMinStaff, stationMaxStaff}`.

**A problem set is meaningless without a date range.** There is no "all problems" — the
horizon is a required input, not a filter applied afterwards.

**Shape-encoding employment type is parked, because the data does not exist.** The sketch
wanted square/circle/hexagon for salaried/temp/per-diem. What exists is `WorkerStatus`
(`WSNone`/`WSActive`/`WSInactive`, which is participation, not employment), a `wcIsTemp`
flag, and `OvertimeModel` (`OTEligible`/`OTManualOnly`/`OTExempt`, whose comment reads
"e.g. per-diem"). The three categories are a combination of the latter two, which
suggests a missing `EmploymentType` concept rather than a rendering choice. Settle the
domain question before drawing the shapes.
