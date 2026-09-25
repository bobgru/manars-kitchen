# A zone is a label on the station, and the three panels are row groups of one table

Piece 4 of the problem view adds the worker and station panels next to the hours panel.
Two decisions were settled by grilling on 2026-09-25 and are recorded here because both
are cheap to make now and expensive to undo later: what a **zone** is, and how the three
panels relate in the page.

A zone is a nullable free-text label on `Station` — `stationZone :: Maybe Text`, a `zone
TEXT` column, `station set-zone` / `station clear-zone`, and `PUT /api/stations/:name/zone`
taking a string or null. Labels are trimmed; blank means none. Stations sharing a label are
grouped under it in the station panel, alphabetically, with stations that have none under
**Unassigned**, last. A zone has no existence apart from the stations that carry it.

The three panels — by hour, by worker, by station grouped by zone — are three `<tbody>`
row groups of **one** table under one day header. Each cell is the most severe kind's
glyph plus a count. Selecting a cell in any panel lists its problems; picking one problem
from that list outlines its hour cell, worker row cell and station row cell across the
panels and says where it is in words.

## Considered Options

**A zone entity with its own table**, list, rename and delete. Rejected for now. The view
needs grouping and a heading, and a label gives both. An entity buys rename-in-one-place
and a stable ordering, and costs a table, a REST surface, a page and the safe-delete
protocol every other entity has grown. If ordering or colour per zone is ever wanted, the
migration is a `zones` table plus a backfill from the distinct labels, which is
mechanical; the reverse is not needed. The cost accepted is that renaming a zone means
retagging each station, and that "Hot line" and "hot line" are two zones.

**One verb with a sentinel for "none"** — `station set-zone grill -` or an omitted argument.
Rejected in favour of `set-zone` plus `clear-zone`, because the audit classifier reads the
raw command line and would need to know the sentinel, and because an omitted argument is
how a typo becomes a silent clear.

**Three tables, one per panel**, each with its own day header. Rejected because vertical
alignment of dates is the entire point of the shared columns, and three tables align only
by accident of equal column widths. One table makes it structural, and gives one
horizontal scroll and one header. The cost is that a panel cannot be collapsed or reordered
independently without splitting the table again.

**Reusing `ScheduleGrid` for the new panels** stays rejected, as ADR 0006 records: the grid
renders assignments as chips, these render an aggregate per cell, and the station panel
needs zone row grouping the grid has no concept of. `ScheduleGrid`'s deferred
`workers-days` and `stations-days` layouts remain undelivered by this work.

**Rows only for workers and stations with a problem in range.** Rejected. An empty row says
"this person is fine", which is information; a panel that lists only the troubled is a
list, not a view. Every active worker and every station has a row. Inactive workers appear
only when a problem names them — a committed assignment can name someone since
deactivated — and are labelled "(inactive)" in words, not only by dimmer text.

**Colour-coded outlines for the cross-panel highlight.** Rejected; the selected cell has a
solid outline, the focused problem's cells a dashed one, and the caption under the list —
"Showing: alex · sandwich · 2026-09-25 15:00" — carries the meaning. Three outlines with
no words is a puzzle, and an outline colour is not something every reader can tell apart.

## Consequences

`Station` gained a fourth field, so its positional constructor sites — the SQLite row
mapper and the JSON instances — changed with it. `StationResp` and the web `StationInfo`
carry `zone`, the Stations list has a Zone column, and the station detail page has a Zone
editor. The export format does **not** carry zones; whether export is meant to be a full
snapshot is an open question in `docs/STATUS.md`, and adding one more field before
deciding would make the answer by accident.

An **unscheduled day** names no worker and no station, so no panel can put it on a row.
Every panel hatches the column, and the header carries the badge, exactly as the hours
panel did alone before. A **day-scoped problem that names a worker** — a period-hours
breach — now has a cell for the first time, in that worker's row; the hours panel still
cannot show it and the notice above the grid says so.

The demo restaurant labels six of its seven stations, leaving `busboy` unassigned on
purpose so the Unassigned group is exercised. Doing that exposed a bug: **name resolution
lost shell quoting**. `resolveInput` split with `shellWords` and rejoined with `unwords`,
so `station set-zone grill "hot line"` came out as five words, parsed as nothing, and did
nothing — silently, because a parse failure in a replay prints nothing. It now re-quotes
with `shellQuote`. Any quoted argument after a resolvable name had this bug, including a
rename to a two-word name.

`npm run e2e:dashboard` no longer depends on the weekday it runs. It used to create a
draft over the whole current period, which contains frozen dates on every day but the
period's first, and it relied on the scheduler leaving a station short. It now drafts from
today and manufactures its problems with a sick call — an absence approved after the
commit — which is the case ADR 0004 is built around and guarantees marks in all three
panels.
