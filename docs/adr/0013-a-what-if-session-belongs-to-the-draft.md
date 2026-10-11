# A what-if session belongs to the draft

`docs/STATUS.md` carried the last piece of the draft-page follow-ons as a design question:
a draft's what-if sessions were not readable over REST in any meaningful sense, because
`GET /api/hints` wanted a session id the browser did not have, and before an endpoint
could be written somebody had to decide whose session a browser means. This records what
grilling settled on 2026-10-10.

The facts the question rested on. A what-if session was keyed by **login**, not by draft
or user: the `hint_sessions` table's primary key was the login session's id plus the draft
id. A web login closed the user's existing active session, including a CLI one, and the
CLI started a fresh session next time, so the old rows were unreachable forever. The web
terminal ran every command under a fake session zero that nobody owned, so what-ifs typed
in the browser pooled into one shared bucket no CLI would see. And the glossary already
defined a what-if session as "the accumulated, persisted what-ifs for one draft". The code
disagreed with the glossary.

## Decisions

**A what-if session belongs to the draft.** Nobody's, in other words: one per draft,
whoever typed it, from whichever client. The table is `what_if_sessions`, keyed by draft
id alone and named with the domain word (ADR 0002 forbids new code naming a what-if a
hint; the repository functions keep their grandfathered names). A migration carries the
most recently updated of each draft's per-login rows across and drops the old table. This
matches the glossary, and it matches ADR 0003: competing experiments are separate drafts,
not separate views of one draft, so two admins what-iffing the same draft are editing the
same thing, as they would be with the draft's assignments.

**Editing a what-if session is an admin action; reading one is not.** The CLI already
required admin for every `what-if` verb that changes anything. The REST and RPC mutators
now require it too, replacing the per-session ownership check, which had nothing left to
check. Reads are open to any authenticated user, like a draft's assignments.

**The browser reads the session under the domain word.** `GET /api/drafts/:id/what-ifs`
returns each what-if with the prose the CLI prints for it, so the page need not know how
to name a station or a skill. The draft page lists them in order under the grid, says the
grid is the draft without them, and says discarding the draft discards them, which the
Discard modal has promised all along and the server has always done.

**The existing `/api/hints` routes keep their shape and ignore the session id.** Deleting
the parameter touches every client and the API spec for no user-visible gain; accepting
and ignoring it keeps them working. Recorded as debt in `docs/STATUS.md`.

**Applying over HTTP is 501.** The REST and RPC `apply` handlers deleted the session and
answered success. They applied nothing: the apply logic, which writes a what-if's effect
to the underlying data, lives only in the CLI. A success code for something that did not
happen is the shape ADR 0005 and the unfreeze stub already warned about, so until the
logic moves into a service both can share, the route says Not Implemented.

**The web terminal runs under the caller's real login session**, resolved from their one
active session, with session zero only as a fallback for a token that outlived its
session. Under the first decision it no longer matters for what-ifs; it still made touch
and close meaningless.

## Considered Options

**Per user.** Survives re-login, but still hides one admin's what-ifs on a shared draft from
another admin, and needs a user id in every request or on every row. Rejected.

**Per login, as it was.** Loses work on every re-login and gives the browser nothing to
show. Rejected.

**Delete the session id from the request types now.** Cleaner, breaking, and the clean-up
can follow once the browser is the only client that matters. Deferred.

**Implement apply on the server.** The right end state, and its own piece: `what-if apply`
in `CLI.App` is a hundred lines that case over six hint kinds and rebuild the session.
Deferred rather than rejected.

## Consequences

**`draft open` no longer asks when there is no terminal.** Resuming a saved session used to
prompt on stdin; the web terminal has none, and with sessions now shared it would hit the
prompt far more often. It resumes without asking when stdin is not a terminal.

**The HTTP session-ownership checks are gone**, from both servers. `repoGetSessionOwner`
stays in the repository for the CLI's session handling.

**Tests.** The integration suite gains four examples: an empty session and a missing draft
read differently; a what-if added under one session id is read back under another, in
words; adding to a missing draft is 404; apply is 501 and deletes nothing. The two
persistence specs lose their session ids, and the test that two sessions could hold two
different what-if lists for one draft now asserts the opposite.

**Debt recorded.** The `/api/hints` session id is accepted and ignored; `apply` over HTTP
is 501; `what-if` in remote-CLI mode still says "not yet supported"; the web terminal's
what-if flow has never been exercised and keeps its in-memory session only for the one
command, so `what-if list` there reads the saved session and nothing more.
