# The draft detail page reports problems without pruning them

`/drafts/:id` shows a draft's assignments as a grid, marks the ones that violate a hard
rule, and warns when the calendar under the draft's own dates has been replaced. It reads
`GET /api/drafts/:id/assignments`, which is backed by `computeDraftViolations` — no
staleness gate, no writes. It does **not** reach `POST /api/drafts/:id/revalidate`, so the
browser has no way to prune a draft even though the CLI's `draft revalidate` and the REST
endpoint both exist. That gap is deliberate.

## Considered Options

**A Revalidate button**, the obvious pairing for the read the page is built on, was
rejected on three grounds. It entrenches behaviour already agreed to be wrong: the
deferred draft-workflow question in `docs/STATUS.md` opens with "pruning is not
rebasing" — a moved calendar should produce a *proposed* update an admin accepts or
rejects, not silent deletion — and putting a prune button in the UI makes that harder to
walk back. The page is strictly more useful without it, because `computeDraftViolations`
can display every violation without destroying anything, and pruning replaces information
with holes. And it cannot be labelled honestly: `pruneDraftViolations` no-ops unless the
calendar has moved, and a client cannot tell whether it will. `isDraftStale` is not
exposed, and `calendarReplacedUnder` is the narrower question "which commits overlap *my*
range" — non-empty implies stale, but not the reverse. So the button would routinely
report "removed 0" with N violations visible above it, which reads as a bug. The
approved-absence case pinned down in `test/DraftValidationSpec.hs` and `test/ApiSpec.hs`
is exactly that.

A button labelled **"Prune invalid assignments"**, which at least says what it does, stays
available as a fallback if a browser-reachable pruning path is ever wanted. What is
rejected is calling it "Revalidate", which sounds like a read.

**Understaffing on this page** was rejected even though it is computable here —
`/api/stations` carries `minStaff`. It is ADR 0004's vocabulary and the problem view owns
it; a second implementation would have to be reconciled later. Empty cells show the holes;
judging them is item 2's job.

**A generic grid taking any two of the four assignment coordinates** (worker, station,
date, hour) as axes was rejected in favour of named layout presets, because empty-cell
meaning is axis-dependent and is most of the component's value. In hours × days a cell is
*closed* (outside that weekday's opening hours), *unstaffed* (open, nobody there), or
staffed — three states the legend explains. In worker × day, "closed" is meaningless and
an empty cell just means that worker is not on that day. A generic grid would hand that
decision back to every caller, leaving a table shell behind and putting the interesting
logic outside the module. Most of the twelve ordered pairs are useless anyway: half are
transposes, and worker × station drops time entirely.

**A commit diff against the calendar** — per cell, added / unchanged / about to be
dropped — is the question an admin actually has before pressing Commit, and is deferred
rather than rejected. It needs a second data source, a three-state cell vocabulary and a
legend on top of a page that did not exist yet.

**Discard on the detail page** was rejected for consistency: no other detail page destroys
its own subject, and discarding needs no information the page provides. **Commit stays**,
because the reverse holds — committing is nothing *but* the information this page shows.
The rule kept is "a detail page does not delete its subject"; commit is not deletion, it
is the draft reaching its purpose, and the row vanishing is bookkeeping.

## Consequences

The page can display a violation that no browser action will clear. That is intended: the
responses to a moved baseline are Generate and Discard, and both are reachable.

Because Commit deletes the draft, the page navigates to `/drafts` on success and hands the
confirmation over in router state — the first place in this UI where a message outlives the
component that produced it. A draft that vanishes underneath the page, whether committed
here, committed elsewhere, or discarded from the list, renders one terminal state whose
wording covers a stale tab and a mistyped URL alike, because the page cannot distinguish
them.

`ScheduleGrid` is extracted from `CalendarPage` rather than copied, and owns the
`MAX_DAYS` range guard, since it is the component that cannot render an oversized range.
Its layout is a prop from the first commit even though only `HoursByDays` exists, so the
remaining layouts and the pivot control are additive.

A draft's saved what-if sessions are **not** shown, because they are not readable over
REST in any meaningful sense: `GET /api/hints` requires both `sessionId` and `draftId`,
the browser has no session id, and the web terminal's hardcoded `SessionId 0` would report
its own what-ifs while a CLI session's — the ones `draft open` resumes — stayed invisible.
Fixing that is a design question about whose session a browser means, not a missing
endpoint.
