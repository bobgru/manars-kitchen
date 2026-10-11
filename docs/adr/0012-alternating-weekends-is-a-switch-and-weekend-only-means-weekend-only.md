# Alternating weekends is a switch, and weekend-only means weekend-only

ADR 0011 turned the alternating-weekends rule on in generation and left a question behind:
the rule had no switch and exempted only weekend-only workers, and `demo/restaurant.txt`
had none of those. Every one of its eleven workers worked the tour's first weekend, so
under the rule nobody could work the second, and Apr 18–19 came out with no assignments
at all. The problem view reported both days unscheduled. This records what was settled
on 2026-10-10.

## Decisions

**The rule is a switch in the scheduler config.** `alternating-weekends`, a `Double` like
every other key, `1.0` by default so nothing changes for existing data; `0.0` turns the
rule off. Not every restaurant alternates weekends, and a rule a restaurant does not have
should be a policy choice, not a constant. `blockedByAlternateWeekend` reads the switch,
and since the scheduler and the validator both ask that one function, turning it off
turns it off in generation and validation alike — there is no way for the two to disagree
about it, which is the discipline ADR 0011 established.

**Weekend-only means weekend-only.** `wcWeekendOnly` was documented as "workers who work
only on weekends", `worker set-weekend-only` was documented as "only schedule on
weekends", and neither was true: the flag was read solely as the exemption from the
alternating-weekends rule, so a weekend-only worker could hold a Tuesday. A new rule,
`blockedByWeekendOnly`, keeps a weekend-only worker off every weekday slot. The scheduler
asks it in `canAssignSlot`, the validator reports it as a `weekend-only` violation, and
`draft diagnose` counts such a worker as off for the day rather than free. It does not
depend on the switch: a restaurant with the alternating rule off still has weekend-only
staff.

**The fixture carries a weekend crew.** Four weekend-only workers — dana, omar, priya and
leo — with sixteen hours a period and, between them, every skill a weekend station needs.
They carry the weekends, and the weekday staff alternate around them to cover what four
people cannot. The rule now has somebody to alternate with, which is what a demonstration
of it needs.

## Considered Options

**A per-worker opt-out only.** Weekend-only already is one. It leaves the rule with no off
position for a restaurant that does not alternate weekends at all. Rejected on its own;
kept as the exemption it always was.

**Switch the rule off in the fixture instead of adding a crew.** Cheapest, and it would
have hidden the rule from every demo rather than showing it working. The tour's
cross-draft revalidation scene exists to show the rule firing. Rejected.

**Mark existing weekday workers weekend-only.** Changes who the weekday staff are and
with it every weekday schedule in every demo. Adding workers who are blocked on weekdays
leaves the weekday schedules alone. Rejected.

**Leave weekend-only as an exemption.** Smaller, but it would put "Weekend-only: yes" on a
worker list beside people working Tuesdays, and leave the README's description false.
Rejected.

## Consequences

**The tour's two weeks after a committed week are staffed again.** Measured over the whole
replay, before and after the crew, with the rule on throughout:

| draft | before | after |
|---|---|---|
| #2, Apr 13–19, the week after the first commit | 340 assigned / 63 unfilled | 399 / 13, 2 understaffed |
| #7, Apr 27 – May 3, the week after the third | 342 / 55, 3 understaffed | 399 / 11, 1 understaffed |
| every other draft | 404–409 / 0–10 | 403–411 / 0–10 |
| cross-draft revalidation removes | 70 assignments | 24 assignments |

Apr 18–19 now holds the weekend crew plus the weekday staff who did not work Apr 11–12
(lucia, sam and the admin). The revalidation scene still removes assignments for the same
reason as before: the two drafts are generated before either is committed, so neither
sees the other's weekend until `draft open` re-validates. It removes fewer because the
weekend crew's assignments are legal.

**Sunday afternoons in the tour are not staffed, and were not before.** With the original
fixture Sunday Apr 12 held grill 10–12, beverage 7–11 and register 7–11 and nothing after
noon; with the crew it holds the same hours, staffed by the crew. That is a scheduler
finding unrelated to this change, recorded in `docs/STATUS.md` item 7.

**Unit tests gain four examples**: the switch off lets a worker take the weekend after one
they worked; a weekend-only worker is not scheduled on a weekday, is scheduled on a
weekend, and stays off weekdays with the switch off. `configKeys` covers 23 parameters.

**`demo-export.json` does not carry weekend-only** — `Export/JSON.hs` preserves it from the
existing context on import. That gap is part of the export question already in
`docs/STATUS.md` item 7 and is not widened here.
