# Drafts may overlap, and commit is last-write-wins with a warning

A draft is an experiment sandbox: its purpose is to try a schedule safely before
anything reaches the calendar. Creating an experiment must therefore never be refused,
so the rule that a draft's date range may not overlap an existing draft's is removed.
Commit remains a whole-range overwrite of the calendar; the protection against
committing two overlapping drafts is a warning plus the existing history snapshot, not
a block and not cross-draft validation.

## Considered Options

**Blocking the second commit** until overlapping siblings are discarded is the safest
option and was rejected because it turns every A/B experiment into an extra step, for a
mistake that is already recoverable.

**Auto-discarding overlapping siblings on commit** was rejected because it destroys
work the admin may still want.

**Cross-draft conflict detection for uncommitted drafts** — flagging that two drafts
both book Marco at grill on Apr 10 — was rejected on the grounds that competing
experiments are *meant* to disagree. The conflict is only real at commit time.

## Consequences

Committing draft A and then draft B over the same dates erases A's assignments
entirely, because `commitToCalendar` deletes the whole date range before inserting
("the date range is the claim, not the assignments"). Two things make that acceptable:
`commitToCalendar` snapshots the assignments it is about to replace into
`calendar_commits` first, so calendar history and checkpoint rollback can restore them;
and commit now returns 409 naming the overlapping drafts, requiring an explicit
`POST /api/drafts/:id/commit/force` or `draft commit --force` to proceed.

Draft staleness detection already existed for the sequential case —
`isDraftStale` compares `diLastValidatedAt` against `repoCalendarCommitsAfter`,
and `pruneDraftViolations` gates on it — and generalises to overlapping drafts
unchanged. What it
does *not* do is notice that the calendar inside a draft's own range was replaced,
because its look-back window is the seven days before the draft's start. That is why
the "replaced by draft #N" message had to be added separately, and it is part of the
larger draft-workflow question deferred in `docs/STATUS.md`.
