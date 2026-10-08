# The scheduler sees what the validator sees

ADR 0005, 0006 and 0010 record a family of defects with one shape: the draft validator and
the scheduler judged the same assignment under different facts, so one of them was wrong
about which schedules are legal. Every instance before this one was the validator reporting
a violation for something the scheduler was entitled to do. The two left on 2026-09-25 ran
the other way — the scheduler produced assignments the validator then rejected — and the
problem view made them visible: 69 `alternating weekends` violations on the feature tour's
Apr 20 – May 3 calendar, and a two-week draft whose second week was judged against the
first week's hours. This records what grilling settled on 2026-10-08.

## Decisions

**A draft is generated one pay period at a time.** `generateDraft` cuts its range with
`payPeriodChunks`, the same cut the validator uses, and builds each chunk under a context
whose period is that chunk's. Each build is seeded with everything built so far, so the
rules that look across days see the previous period and the optimizer, which never destroys
a seeded assignment, leaves it alone. Unfilled lists concatenate; overtime maps add, since
each is one period's. A single-period draft is built exactly as before.

**The seven days of calendar before the draft join the generation seed.** The validator has
always joined this look-back onto the schedule it judges; generation started from the
draft's own assignments alone, so a draft beginning on Monday could not see Sunday's closing
shift for the rest rule, nor last weekend for the alternating-weekends rule. The look-back
is context, not material: it is stripped from the result before the draft is saved or
returned, hill climbing proposes swaps only among the slots being built, and its hours are
excluded from the committed-hours map by `loadValidationContextExcluding` because the
schedule already holds them.

**The alternating-weekends rule reads the schedule.** "Worked either day of the weekend one
week before this slot", answered from the schedule under judgement or construction, like
every other rule that looks across days. The static `schPrevWeekendWorkers` set is deleted.
The first weekend of a range sees the look-back; every later weekend sees the one before it
in the same schedule — which the set could never do, so a range holding two weekends, or a
two-week draft, had its second weekend checked against nothing. That gap was the
validator's too, and closes with it.

**The rule is on in generation.** This reverses the decision of 2026-09-07 to leave it off.
The reason for leaving it off — that closing it restricts what the scheduler may do, and
so changes schedules rather than only changing which are called legal — still holds, and is
accepted: the dashboard was reporting the schedules it produced as illegal.

## Considered Options

**Per-period hour counts inside one context.** Replace `schPeriodBounds` and
`schCalendarHours` with a function of the day, so one build spans periods. Rejected: it
changes the inputs of `canAssignSlot` and every hour rule, hint session and diagnosis that
reads them, and it makes the glossary's "the context holds one period" false. Building per
period reuses the cut the validator already makes and gives the cross-period seed for free.

**Keep a static previous-weekend set and fill it in for generation.** The smallest change,
and it would have left both the scheduler and the validator blind to a second weekend
inside one range. Rejected once the seed carried the look-back, which made the set
redundant.

**Leave the rule off and stop reporting it.** Consistent, but it deletes a rule the
restaurant has. Rejected.

## Consequences

**Both of the tour's committed fortnights now report no violations.** Apr 20 – May 3 went
from 69 `alternating weekends` violations to none; Apr 6 – 19 stays at none. Compromises
and unscheduled days are unchanged in kind.

**The tour staffs fewer weekend slots, and that is the rule's cost made visible.** Measured
over the whole replay, before and after:

| draft | before | after |
|---|---|---|
| #2, Apr 13–19, the week after the first commit | 408 assigned / 8 unfilled | 340 / 63 |
| #7, Apr 27 – May 3, the week after the third | 408 / 5 | 342 / 55, 3 understaffed |
| every other draft | 404–409 / 0–10 | unchanged within one or two |

The missing slots are the weekends. Apr 18–19 holds no assignments at all, and the problem
view reports both days as unscheduled. `demo/restaurant.txt` has no weekend-only worker,
and every worker it has worked Apr 11–12, so under an alternating-weekends rule nobody may
work Apr 18–19. The scheduler used to staff that weekend anyway and the validator used to
flag every hour of it; now they agree. Whether the rule should be unconditional — it has no
switch, and exempts only weekend-only workers — or whether the fixture should carry a
second weekend crew, is the open question this leaves, recorded in `docs/STATUS.md`. The
cross-draft revalidation demo in the tour still removes 70 assignments: the two drafts it
uses are generated before either is committed, so neither can see the other's weekend
until `draft open` re-validates.

**The scheduler now sees the calendar before the draft for every cross-day rule**, not just
the weekend one: rest period and consecutive hours across a draft's first morning were the
same blindness, and close with the same seed.

**What `docs/STATUS.md` said about the multi-period draft was wrong in direction.** It
said week two's caps were not enforced. Week two was judged against week one's total: a
worker at their cap in week one got nothing in week two, and one under it shared the
remainder. The regression test asserts both weeks land under the cap and above zero.

**The what-if and hint sessions are untouched.** The three sites in `src/CLI/App.hs` that
build a `SchedulerContext` by hand still use the draft's range as the pay period, an empty
committed-hours map and no look-back. They are the next instance of this family, and are
recorded rather than fixed here.
