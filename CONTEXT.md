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
pins, edited privately, and either committed to the calendar or discarded.
Drafts do not overlap each other.

**Commit**:
The act of replacing a date range of the calendar with a draft's assignments,
and the history record it leaves behind. The date range is the claim: dates in
range with no assignment are cleared, not skipped.

**Named schedule**:
The superseded artefact — a set of assignments stored under a text name, with no
date-range identity and no relationship to the calendar. Retained for the CLI's
`schedule *` commands only. New work uses drafts and the calendar.
_Avoid_: treating this as the current model, or as a synonym for **Schedule**.

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
Producing the hints for a draft, a named schedule, or a calendar range.

**Rebase**:
Re-examining a what-if session after the data beneath it changed, classifying
each what-if as irrelevant, compatible, conflicting, or structural.

**Generate**:
Running the scheduler over a draft, using the draft's current assignments as the
seed. Generating overwrites the draft's assignments; it does not touch the
calendar.

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
