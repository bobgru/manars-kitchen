# Drafts and the calendar supersede named schedules

The system grew two ways to build a schedule: a **named schedule** (`Service.Schedule`,
the `schedules` + `assignments` tables, the `schedule *` and `assign`/`unassign`
commands) and a **draft** committed to the continuous calendar (`Service.Draft`,
`draft_assignments`, `calendar_assignments`). The web admin UI targets drafts and the
calendar, and the named-schedule surface is removed rather than left in place as a
second way to do the same thing.

## Considered Options

Building `POST /api/schedules` plus assign/unassign REST for the named path was the
option STATUS item 1 originally assumed. It was rejected because the named path is
strictly the weaker scheduler: `createSchedule` hardcodes `schClosedSlots = empty`,
`schPrevWeekendWorkers = empty` and `schCalendarHours = empty`, and derives period
bounds from the slot list — so it ignores station closures, pay-period boundaries and
hours already worked in the calendar. `generateDraft` feeds all of those in. Drafts
also already had six working REST endpoints; named schedules had three read/delete
endpoints and no create.

Leaving the named path in place, deprecated, was rejected because there are no end
users yet apart from the demo, so the cost of removal is at its lowest now and the
cost of two parallel models is paid on every subsequent change.

## Consequences

Removal is not confined to `Service.Schedule`. Four dependencies were load-bearing:
`calendar commit <schedule-name> <from> <to>` sourced its assignments from a named
schedule and is removed with no replacement other than `draft commit`; the export /
import JSON format carried a `schedules` key; worker safe-delete counted
named-schedule assignments as `wrSchedule` in `WorkerReferences`; and the demo's first
scheduling section was written against `schedule create` / `schedule view`.

The `schedules` and `assignments` tables are no longer created, but no `DROP TABLE`
migration was added — existing databases keep them as unreferenced orphans. This
codebase has no migration framework and this was not the place to introduce one.
