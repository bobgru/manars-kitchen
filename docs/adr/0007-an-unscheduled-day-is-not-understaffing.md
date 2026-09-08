# An unscheduled day is reported once, and is not understaffing

Understaffing presupposes an attempt to staff. A day inside a problem view's horizon that
holds **no assignments at all**, while at least one station expects somebody, is reported
as a single `PUnscheduled` problem for that day, and its station-slots are **not** also
reported understaffed. `Problem` gains a fourth constructor, ranked above understaffing and
below violation.

This refines ADR 0006, which describes `Problem` as a three-constructor sum; that count is
now four, and `problemStation` is `Nothing` for one more kind.

Piece 3 of the problem view made the question unavoidable. Point `/` at a pay period nobody
has scheduled — which the demo fixture does, its calendar being April 2026 — and the old
rule reported **630 understaffing problems per fortnight**: every open station-slot, empty
because nothing at all had been built. Technically true, and it drowned the one fact the
admin needed, which is that the period does not exist yet.

`CONTEXT.md` already drew the neighbouring line: a station whose minimum is zero is not
understaffed by having nobody, it is simply not being staffed. The decision here is that
the same reasoning extends from a station to a day.

## Considered Options

**Leave it at 630.** Honest, and counts stay comparable across periods. Rejected because
comparability is not what the number is for: the view exists to answer "what should I do
today", and a count that reads the same whether one station is thin or nothing exists
answers it worse than a sentence would. The horizon marks did distinguish the two cases by
magnitude, which asks the reader to know that 630 means "empty" and 40 means "problems" —
a fact about the fixture, not about the restaurant.

**Only report understaffing where the day already has at least one assignment**, and report
nothing else. The smallest change, and it fixes the noise. Rejected because it loses the
message entirely: an unscheduled fortnight would render as *clear*, which is worse than
overcounting. A view whose job is to surface problems must not go quiet on the largest one.

**Report unscheduled per station-slot rather than per day**, so it slots into the existing
cell aggregation with no new scope. Rejected because it is the same 630 items with a
different label. The point of the decision is that the fact is about the day.

**A separate endpoint or flag** — `GET /api/problems` plus something like
`unscheduledDays` — was rejected for the reason ADR 0006 gives for one endpoint: a second
source is the mechanism by which the projections stop agreeing. An unscheduled day is a
problem an admin must act on, so it belongs in the problem set.

**Ranking it above violation.** Rejected. A violation is a rule broken by something that
exists; an unscheduled day is work not yet started, and it is not a labour-rule breach. It
does outrank understaffing, because a day nobody is on blocks more than a thin station does.
As ADR 0006 notes, severity decides only which kind a *cell* announces, so this choice
stays low-stakes.

## Consequences

`computeUnderstaffing` becomes `computeStaffingProblems`, returning both kinds, because they
are alternatives and only one function can decide which applies. Suppression is per day, not
per station: any assignment anywhere on the day — including one onto a zero-minimum
station — counts as the attempt, since the question is whether the day was worked on.

**A day on which nothing is expected is neither unscheduled nor understaffed.** If every
station is closed or at a zero minimum, the day is a day off, and the existing
zero-minimum test now covers that too.

`PUnscheduled` is the first `ScopeDay` problem to exist, so the hours view had to grow a
place to put one. It goes in the **column header**, as `○ not scheduled` in words, with the
day's cells hatched rather than tinted — texture, not hue — and a sentence above the grid
saying it once for the range. An empty column with no header badge reads as a day with
nothing wrong, which is the opposite of the truth. The generic "these problems affect whole
days and are not placed in the grid" line stays for whatever `ScopeDay` kind comes next.

The demo fixture's opening screen goes from 630 problems to 14, and `npm run e2e:dashboard`
had to be rewritten around that: its detail-pane assertions now run *after* it commits a
draft, because an unscheduled day offers no cell to click.
