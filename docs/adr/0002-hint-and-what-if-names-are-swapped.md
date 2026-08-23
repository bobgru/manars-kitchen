# The code names for "hint" and "what-if" are swapped, and stay that way

The domain has two distinct concepts: a **what-if** is an admin-driven hypothetical
change to a draft ("pin Marco here", "close the grill at 9:00"), and a **hint** is an
automated suggestion the system derives from a schedule it could not fill ("hire a
worker with these skills", "train this worker"). The code has these names swapped —
`Domain.Hint` holds what-ifs, `Domain.Diagnosis` holds hints — and we chose to record
that rather than rename, because the rename buys nothing functional and costs a REST
path, a table name and four specs.

## Considered Options

Renaming `Hint` → `WhatIf` and `Diagnosis` → `Hint` to match the domain would touch
`POST /api/hints`, the `hint_sessions` table, `Service.HintRebase`, and the
`hint-cli`, `hint-persistence`, `hint-rebase` and `hint-session` specs. It is a
breaking change across the REST surface and the schema for zero behavioural gain.

Leaving it undocumented was rejected because the mismatch is invisible: a reader who
opens `Domain.Hint` expecting suggestions finds `CloseStation`, `PinAssignment`,
`AddWorker`, `WaiveOvertime`, `GrantSkill` and `OverridePreference` — every one of them
reachable only from a `what-if <verb>` command — and has no way to know the naming was
deliberate.

## Consequences

**No new code may name a what-if a "hint".** New identifiers, endpoints, UI labels and
spec text use the domain words from `CONTEXT.md`. The existing names are grandfathered,
not a precedent.

The collision has a natural escape hatch: `diagnose` has no REST endpoint at all today,
so the suggestion side of the API is unclaimed and a future
`GET /api/drafts/:id/diagnosis` can carry the domain word cleanly without colliding
with `/api/hints`.
