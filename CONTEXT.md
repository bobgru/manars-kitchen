# Manar's Kitchen

Shift scheduling for a restaurant: who works which station, when. One backend
serves three clients — the CLI, the admin browser UI, and the worker browser UI.

## Language

### Scheduling artefacts

**Assignment**:
One worker at one station for one slot. The atom everything else is built from.

**Slot**:
A date, a start time, and a duration. Not a shift.

**Shift**:
A named, reusable time-of-day window (e.g. "morning") that slots are generated
from. A shift is a template; a slot is a concrete occurrence.

**Schedule**:
An unnamed, unidentified set of assignments — the domain's value type. A schedule
is a *value*, never a stored entity with a life cycle.
_Avoid_: using "schedule" for a draft, the calendar, or a named schedule.

**Calendar**:
The single authoritative record of what is actually scheduled, unbroken across
time and not divided into named periods. The only artefact workers see.

**Draft**:
A working copy of assignments over a date range, seeded from the calendar and
pins, edited privately, and either committed to the calendar or discarded. Any
number of drafts may cover the same dates — competing experiments over one week
are the point, and are *meant* to disagree, so creating one is never refused for
overlap. The disagreement only becomes real at commit time. See ADR 0003.

**Commit**:
The act of replacing a date range of the calendar with a draft's assignments,
and the history record it leaves behind. The date range is the claim: dates in
range with no assignment are cleared, not skipped. Because the whole range is
overwritten, committing one of two overlapping drafts erases the other's work
from the calendar; that is refused unless forced (`draft commit --force`,
`POST /api/drafts/:id/commit/force`), and recoverable from the history snapshot
either way. Overlapping siblings are never auto-discarded.

**Named schedule**:
The removed artefact — a set of assignments stored under a text name, with no
date-range identity and no relationship to the calendar. Deleted outright; there
is no `schedule create`, `assign` or `unassign`. Every schedule is built inside a
draft and reaches the calendar by committing that draft.
_Avoid_: using this term for anything current. A reference to it in
documentation or a comment is stale, not a description of a surface that exists.

### Editing a draft

**Pin**:
A standing instruction that a worker occupies a station on a recurring weekly
basis. Pins seed every draft and outrank the calendar when the two disagree.

**What-if**:
One hypothetical change an admin adds to a draft to see its effect — pin this
worker here, close this station, waive this worker's overtime, grant this worker
a skill. Admin-driven and reversible. What-ifs are the *only* way an admin edits
a draft's assignments by hand; there is no direct assign/unassign on a draft.

**What-if session**:
The accumulated, persisted what-ifs for one draft, replayable and rebasable
against later changes to the underlying data.

**Hint**:
One automated suggestion the system derives from a schedule it could not fill —
hire a worker with these skills, train this worker, give these workers overtime,
close this station, bring in a temp. System-driven, and never applied on its own.
_Avoid_: using "hint" for a what-if. A hint proposes; a what-if enacts. Each hint
names the what-if an admin could add in response.

**Diagnose**:
Producing the hints for a draft or a calendar range.

**Rebase**:
Re-examining a what-if session after the data beneath it changed, classifying
each what-if as irrelevant, compatible, conflicting, or structural.

**Generate**:
Running the scheduler over a draft, using the draft's current assignments as the
seed. Generating overwrites the draft's assignments; it does not touch the
calendar.

### Problems

**Problem**:
Something about a set of assignments that wants an admin's attention. Always
scoped to a date range — there is no "all problems". A problem knows which
entities it touches: at most one worker, at most one station, and a date or slot
scope. Some touch only two of the three.
_Avoid_: using "problem" loosely for a bug in the software.

**Violation**:
The kind of **Problem** where an existing assignment breaks a hard rule — skill
qualification, absence, alternating weekends, period or daily hours, rest period,
consecutive hours, avoid-pairing. Something is scheduled that should not be.
_Avoid_: treating overtime as one. Overtime past a worker's regular hours is a
violation only when it is not **Authorised overtime**, and the daily rule's hard
ceiling is the maximum hours in a day, not the non-overtime threshold below it.

**Authorised overtime**:
Hours past a worker's regular per-period limit that their overtime model and opt-in
permit — an `OTExempt` worker always, an `OTEligible` worker who opted in, an
`OTManualOnly` worker never. Legal, and therefore not a **Violation**; it is a
**Compromise**, because someone is working more than their stated limit even though
they agreed to. `Domain.Worker.exceedsPermittedHours` is the one predicate that
decides this, and both the scheduler and the draft validator ask it.
_Avoid_: reading `wouldBeOvertime` as "is illegal". It answers only "is this
overtime", which is a different and much weaker claim.

**Compromise**:
The kind of **Problem** where an assignment is legal but ignores a stated
preference — a worker's station preference, their wish for variety, their hour
headroom, or **Authorised overtime**. Nothing is broken; someone did not get what
they wanted.
_Avoid_: listing a worker's **shift preference** among these. The scheduler never
reads `wcShiftPrefs` — it is stored, set, displayed and exported, and no scheduling
code consults it — so an unhonoured shift preference is a missing feature rather
than a compromise anyone made. See ADR 0006.
_Avoid_: calling this a soft violation. Nothing is violated, so the word invites
the reader to treat it as a **Violation**.

**Understaffing**:
The kind of **Problem** where a station has fewer assignments than its minimum
staffing for a slot. A station whose minimum is zero is not understaffed by
having nobody — it is simply not being staffed.
_Avoid_: reporting it on a day that is **Unscheduled**. Understaffing presupposes
an attempt to staff.

**Unscheduled**:
The kind of **Problem** where a day expects staff and holds no assignments at
all — not "everything is wrong with this day" but "this day has not been built
yet". Reported once for the day, in place of its stations' **Understaffing**, and
about no worker and no station. A day on which every station is closed or at a
zero minimum is not unscheduled; nothing was expected of it. See ADR 0007.
_Avoid_: treating it as the sum of its slots. It is one fact about the day, which
is why it outranks **Understaffing** and is scoped to a date rather than a slot.

**Unfilled**:
A station and slot the scheduler could not staff. The raw fact, and not yet a
judgement: an unfilled slot is **Understaffing** only where the station's minimum
staffing is above zero and the day has been staffed at all.

**Horizon**:
The date range a problem view is scoped to — today, the current pay period, or
the next one. Derived from the **Pay period**, so it follows however the
restaurant is paid rather than assuming a week.

### Time boundaries

**Freeze line**:
Yesterday. Dates on or before it are frozen — the past is not to be rewritten.

**Unfreeze**:
A temporary, explicitly bounded permission to modify frozen dates, cleared once
a commit touching frozen dates lands.

**Pay period**:
The interval that overtime and hour limits are measured over. Independent of
draft date ranges, which may cover any span.

### People

**User**:
An authenticated account. Every user has a role; only some users are workers.

**Worker**:
A user who can be assigned to stations. A worker's identity *is* their user
identity — `WorkerId` and `UserId` denote the same person.

**Station**:
A place in the kitchen that needs staffing, requiring particular skills.

**Skill**:
A capability a worker holds and a station requires. Skills may imply other
skills.
