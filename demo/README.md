# Demo scenarios

Each file here is a replay script: one CLI command per line, `#` for comments,
blank lines ignored. `include <path>` splices in another script, resolved relative
to the including file's own directory.

```bash
stack exec manars-cli -- --demo demo/<scenario>.txt --no-delay
```

Every run **wipes and rebuilds `demo-db/demo.db`**, so a scenario is a fixture you
can regenerate rather than a database you have to keep. `--no-delay` runs flat out;
`--delay 600` puts 600 ms between commands, which is what you want when watching,
or when the behaviour under test depends on distinct millisecond timestamps.

| file | what it is |
|---|---|
| `restaurant.txt` | The restaurant itself — shifts, skills, stations, workers, their skills, hour caps, statuses, preferences, seniority. No dates and no schedule. Included by the scenarios rather than copied into each. |
| `restaurant-setup.txt` | The feature tour: every CLI surface in order, against a **fixed historical week** (April 2026). The default for `--demo` with no file. |
| `current-period.txt` | A restaurant whose calendar covers **today**. This is the fixture to use when looking at the web UI. |

## Which fixture do I want?

**Looking at the app?** `current-period.txt`. The problem view at `/` scopes
everything to today, this pay period and the next, so a fixture pinned to April
2026 leaves every horizon empty and the whole screen reads "not scheduled". This
one staffs the current period, then approves an absence *after* committing — so
the calendar holds assignments that are no longer valid without the calendar
having changed, which is the case the problem view exists for — and leaves the
next period empty so the "not scheduled" state is visible beside a staffed one.

**Exercising CLI behaviour, or the freeze line?** `restaurant-setup.txt`. Its
dates have to stay historical: the freeze-line section demonstrates that the past
is protected, which needs dates in the past. Note that **every draft id in it is
positional** — inserting or removing a `draft create` shifts the rest.

## Dates

Any command that takes a date accepts `YYYY-MM-DD`, `today`, `today+N` or
`today-N`. Relative forms are what let a scenario stay correct however long after
it was written it is run; see ADR 0008. A scenario that must reproduce a specific
historical situation should use ISO dates, and say why.

## Adding a scenario

Start with `include restaurant.txt`, then set a pay period, then build only the
state your scenario is about. Keep it in this directory, add a row to the table
above, and prefer relative dates unless the scenario is *about* particular dates.

If you find yourself copying more than a couple of lines from another scenario,
that shared part belongs in its own file with an `include` — which is why
`restaurant.txt` exists.
