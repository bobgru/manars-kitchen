# Compromises are per assignment and hideable, and a pin displaces what it makes illegal

Piece 5 of the problem view adds **Compromise**, the fourth kind of problem, and the
smaller items beside it fixed three ways the calendar could hold violations the scheduler
never saw. This records the decisions, settled by grilling on 2026-09-25, and the findings.

## Decisions

**A compromise is reported per assignment, like a violation.** `PCompromise Assignment
CompromiseKind`, one per assignment per kind. It names a worker, a station and a slot, so it
lands in all three panels through the plumbing violations already use, and each has a
sentence. The three kinds are exactly the ones ADR 0006 derived — authorised overtime,
station not preferred, variety repeat — and no others. An assignment that is a violation
is never also a compromise: a broken rule outranks a disappointed preference.

**Compromises count, and can be hidden.** They are problems by the glossary, so the horizon
segments count them. But one opted-in overtime worker generates one per hour, and the demo
week holds 121 of them beside 7 violations, so a segment reading "128 problems" would bury
the seven. A "Show compromises" checkbox above the grid, on by default and remembered per
browser, drops them from the counts, the panels and the detail pane at once. Cells already
announce their most severe kind, so a mixed cell never reads as a compromise.

**A pin displaces a calendar hour it makes illegal.** Draft seeding merges the calendar
with the expanded pins, pins winning on the same (worker, date, start). Precedence now also
covers proximity: on a day where a worker has a pin, a calendar hour of theirs that the
pin's presence makes illegal — a run past the consecutive ceiling, a broken rest period, a
day over its maximum — yields to the pin. Workers and days without a pin are untouched.

## Considered Options

**Aggregating compromises per worker per day.** Fewer items, but the detail pane then
explains a bundle and the hour panel has nothing to show. Rejected; the checkbox handles
volume without losing the per-hour fact.

**No filter.** Simplest, and the segment count becomes the least useful thing on the page.
Rejected for the reason above.

**Re-validating the whole calendar when seeding a draft.** The general form of the pin fix:
keep a calendar assignment only if it is legal against everything seeded before it. Rejected
for now because it changes what "seed from the calendar" means — a new draft would silently
drop committed hours that became illegal for any reason, which is the pruning-without-a-
report that the draft workflow section of `docs/STATUS.md` already objects to. The
narrow rule is about what a pin displaces, which is what pin precedence has always meant.

**Making `needsBreak` bidirectional for everyone.** The validator asks "is this assignment
the hour too many", and that is the right question for reporting: the tail of a run is the
violation, not every hour in it. The scheduler asks "would adding this create a run that is
too long anywhere", which is different once pins seed hours ahead of the fill order. So the
scheduler got its own predicate, `wouldExceedConsecutive`, and the validator kept
`needsBreak`. Two questions, two predicates; not two copies of one.

## Consequences

**Three ways the calendar held violations the scheduler never saw are closed.**

- The seven-day look-back the validator joins onto a schedule was also counted through the
  committed-hours map when it fell inside the pay period, so a mid-period draft charged
  those days twice and a worker exactly at their cap was reported over it — 24 violations
  in the regression test, for a legal week. `loadValidationContextExcluding` takes the
  look-back's start as the exclusion. Fifth instance of the family in ADR 0005 and 0006.
- A range spanning two pay periods was judged against one context, whose period is the
  range's first. Assignments in the second period added nothing to the hour count and
  were judged on the first period's total. The problem view's request covers the current
  period and the next, so it always spanned two. `payPeriodChunks` cuts a range at period
  boundaries and both `validateSchedule` and `computeProblems` judge each chunk with its
  own context.
- The tour's five consecutive-hours violations on the days it pins Marco were two things:
  the scheduler filling the hour before a pin without seeing the pin as the hour too
  many, and a seed carrying a committed hour beside a pin added after the commit. Both
  fixed as above; the tour's two committed weeks now report no violations.

**The scheduler still holds one pay period.** `generateDraft` builds the whole draft under a
context whose period is the draft's first, so a two-period draft has its hour caps enforced
in the first period only. The validator now reports what that produces, honestly. Fixing
generation means building per period or carrying period-aware hour counts; it is recorded
in `docs/STATUS.md` rather than done here.

**`calendar hours` now counts hours worked**, distinct (worker, slot) pairs, not assignment
rows, so multi-station coverage no longer shows as overtime the validator does not report.

The demo restaurant gives Tony a variety preference so the fixture produces all three
kinds. The `compromise` browser demo tells the story and ends by adding a station to the
heaviest worker's preference list in the terminal, so the view shows compromises
disappearing without anything being rescheduled — a preference change is not a calendar
change, and the page hears it anyway.
