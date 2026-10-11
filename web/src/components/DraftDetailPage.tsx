import { useState, useEffect, useCallback, useMemo } from "react";
import { useParams, useNavigate, useSearchParams, Link } from "react-router";
import {
  fetchDraft,
  fetchDraftAssignments,
  fetchDraftWhatIfs,
  generateDraft,
  describeCommit,
  type DraftInfo,
  type DraftAssignments,
  type WhatIf,
} from "../api/drafts";
import {
  fetchNameMaps,
  fetchFreezeLine,
  fetchCalendar,
  type Assignment,
  type NameMaps,
} from "../api/calendar";
import { useEntityEvents } from "../hooks/useSSE";
import ScheduleGrid from "./ScheduleGrid";
import GridLayoutControl from "./GridLayoutControl";
import CommitDraftDialog from "./CommitDraftDialog";
import {
  assignmentKey,
  slotHour,
  pad2,
  diffAgainstCalendar,
  describeCommitDiff,
  parseLayout,
  DEFAULT_LAYOUT,
  type GridLayout,
} from "../lib/grid";

const EMPTY_NAMES: NameMaps = { workers: new Map(), stations: new Map() };

/**
 * One draft's assignments as a grid, with the hard-rule violations among them
 * named underneath.
 *
 * There is deliberately no way to prune from here, though
 * `POST /api/drafts/:id/revalidate` exists and the CLI's `draft revalidate` uses
 * it. The violations shown come from `computeDraftViolations`, which has no
 * staleness gate, so this page reports problems that pruning would silently
 * delete and that it would often refuse to touch at all. The responses to a moved
 * baseline are Generate and Discard. See ADR 0005.
 *
 * Discard is on the drafts list, not here: no other detail page destroys its own
 * subject, and discarding needs nothing this page knows. Commit stays, because
 * deciding whether to commit is the entire reason to read this page.
 */
export default function DraftDetailPage() {
  const { id: rawId } = useParams<{ id: string }>();
  const draftId = Number(rawId);
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const layout = parseLayout(searchParams.get("layout"));

  /** In the URL like the calendar's range, so a view can be linked to. */
  function changeLayout(l: GridLayout) {
    setSearchParams(l === DEFAULT_LAYOUT ? {} : { layout: l }, { replace: true });
  }

  const [draft, setDraft] = useState<DraftInfo | null>(null);
  const [detail, setDetail] = useState<DraftAssignments | null>(null);
  const [names, setNames] = useState<NameMaps>(EMPTY_NAMES);
  const [freezeLine, setFreezeLine] = useState("");
  /**
   * The calendar over the draft's own range, for the commit diff. Null when it
   * could not be read: the page then shows the draft without comparing it,
   * rather than comparing it with an empty calendar and calling everything new.
   */
  const [calendar, setCalendar] = useState<Assignment[] | null>(null);
  /** The draft's what-if session; null when it could not be read. */
  const [whatIfs, setWhatIfs] = useState<WhatIf[] | null>(null);

  const [loading, setLoading] = useState(true);
  const [gone, setGone] = useState(false);
  const [error, setError] = useState("");
  const [toast, setToast] = useState("");
  const [busy, setBusy] = useState(false);
  const [committing, setCommitting] = useState(false);

  const load = useCallback(async () => {
    if (!Number.isInteger(draftId)) {
      setGone(true);
      setLoading(false);
      return;
    }
    try {
      setError("");
      setGone(false);
      // The draft and its assignments are the page; the others only decorate
      // it, so they fall back rather than taking it down.
      const [info, assignments, maps, freeze, session] = await Promise.all([
        fetchDraft(draftId),
        fetchDraftAssignments(draftId),
        fetchNameMaps().catch(() => EMPTY_NAMES),
        fetchFreezeLine().catch(() => ""),
        fetchDraftWhatIfs(draftId).catch(() => null),
      ]);
      // Needs the draft's range, so it waits for the draft.
      const cal = await fetchCalendar(info.dateFrom, info.dateTo).catch(() => null);
      setDraft(info);
      setDetail(assignments);
      setNames(maps);
      setFreezeLine(freeze);
      setCalendar(cal);
      setWhatIfs(session);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("404")) setGone(true);
      else setError(msg);
    } finally {
      setLoading(false);
    }
  }, [draftId]);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  useEntityEvents("draft", load);
  // A commit elsewhere is what moves this draft's baseline, which is what the
  // replaced-calendar warning and every violation below are computed against.
  useEntityEvents("calendar", load);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }

  /**
   * Constraint prose per violating assignment. `validateAssignment` is a guard
   * chain returning at most one violation per assignment, so this is a map and
   * not a multimap.
   */
  const marks = useMemo(() => {
    const index = new Map<string, string>();
    for (const v of detail?.violations ?? []) {
      index.set(assignmentKey(v.assignment), v.constraint);
    }
    return index;
  }, [detail]);

  const markFor = useCallback(
    (a: Assignment) => marks.get(assignmentKey(a)),
    [marks]
  );

  /**
   * What Commit would do to the calendar: the question this page exists to
   * answer, and the trap ADR 0003 makes common -- a commit claims its whole
   * range, so whatever the calendar holds there and the draft does not is
   * dropped, not kept.
   */
  const diff = useMemo(
    () => (detail && calendar ? diffAgainstCalendar(detail.assignments, calendar) : null),
    [detail, calendar]
  );

  function workerName(id: number): string {
    return names.workers.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number): string {
    return names.stations.get(id) ?? `station ${id}`;
  }

  async function handleGenerate() {
    setBusy(true);
    try {
      const result = await generateDraft(draftId);
      showToast(
        `Generated ${result.schedule.length} assignment(s), ` +
          `${result.unfilled.length} unfilled.`
      );
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <div className="page loading">Loading draft...</div>;

  if (gone) {
    return (
      <div className="page">
        <Link to="/drafts" className="back-link">
          &larr; Back to Drafts
        </Link>
        {/* This page cannot tell a stale tab from a mistyped URL, so the wording
            does not pretend to. Committing and discarding both delete a draft. */}
        <p>Draft #{rawId} does not exist. It may have been committed or discarded.</p>
      </div>
    );
  }

  if (!draft || !detail) {
    return <div className="page msg-error">{error || "Failed to load draft."}</div>;
  }

  const violations = detail.violations;

  return (
    <div className="page">
      <Link to="/drafts" className="back-link">
        &larr; Back to Drafts
      </Link>
      <h2>Draft #{draft.id}</h2>

      {error && <div className="msg-error">{error}</div>}
      {toast && <div className="msg-success">{toast}</div>}

      {/* Above the grid because it invalidates the grid: everything below was
          reasoned against a baseline that has since moved. */}
      {detail.replacedUnder.length > 0 && (
        <div className="msg-warn">
          Warning: the calendar under these dates was replaced by{" "}
          {detail.replacedUnder.map(describeCommit).join(", ")}. This draft was
          built on a baseline that no longer exists.{" "}
          <Link to={`/calendar?from=${draft.dateFrom}&to=${draft.dateTo}`}>
            See what the calendar holds now
          </Link>
          .
        </div>
      )}

      <div className="detail-section">
        <h3>Draft</h3>
        <div className="form-row">
          <label>Date range:</label>
          <span>
            {draft.dateFrom} to {draft.dateTo}
          </span>
        </div>
        <div className="form-row">
          <label>Created:</label>
          <span>{draft.createdAt}</span>
        </div>
        <div className="form-row">
          <label>Last validated:</label>
          <span>{draft.lastValidatedAt}</span>
        </div>
        <div className="form-row">
          <label>Assignments:</label>
          <span>{detail.assignments.length}</span>
        </div>
        <div className="form-row">
          <label>On commit:</label>
          {/* Dropping something is the surprise; say it louder than the rest. */}
          <span
            className={diff && diff.dropped.length > 0 ? "msg-warn" : undefined}
            data-testid="commit-diff"
          >
            {diff
              ? describeCommitDiff(diff)
              : "Could not read the calendar over these dates to compare."}
          </span>
        </div>
        <div className="action-bar">
          <button className="btn" disabled={busy} onClick={handleGenerate}>
            {busy ? "Generating..." : "Generate"}
          </button>
          <button className="btn" disabled={busy} onClick={() => setCommitting(true)}>
            Commit
          </button>
          <span className="text-muted">
            Discard is on the Drafts list. Generating overwrites this draft's
            assignments and does not touch the calendar.
          </span>
        </div>
      </div>

      <div className="detail-section">
        <h3>Assignments</h3>
        {detail.assignments.length === 0 ? (
          <p className="text-muted">
            Nothing in this draft yet. Generate to fill it.
          </p>
        ) : (
          <>
            <GridLayoutControl value={layout} onChange={changeLayout} />
            <ScheduleGrid
              layout={layout}
              assignments={detail.assignments}
              from={draft.dateFrom}
              to={draft.dateTo}
              names={names}
              freezeLine={freezeLine}
              markFor={markFor}
              baseline={calendar ?? undefined}
            />
          </>
        )}
      </div>

      <div className="detail-section">
        <h3>Violations ({violations.length})</h3>
        {violations.length === 0 ? (
          <p className="msg-success">
            No assignment in this draft breaks a hard rule.
          </p>
        ) : (
          <>
            {/* Said in words, because the only other cue is a mark on a chip. */}
            <p className="msg-warn">
              These assignments are still in the draft — this is a report, not a
              removal. Nothing here is fixed by re-reading the page; regenerate or
              discard.
            </p>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Hour</th>
                  <th>Worker</th>
                  <th>Station</th>
                  <th>Constraint</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                {violations.map((v) => (
                  <tr key={assignmentKey(v.assignment)}>
                    <td>{v.assignment.slot.date}</td>
                    <td>{pad2(slotHour(v.assignment))}:00</td>
                    <td>{workerName(v.assignment.worker)}</td>
                    <td>{stationName(v.assignment.station)}</td>
                    <td>{v.constraint}</td>
                    <td>{v.reason}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </div>

      <div className="detail-section">
        <h3>What-ifs{whatIfs ? ` (${whatIfs.length})` : ""}</h3>
        {/* The grid above is the draft as saved. A what-if is a hypothesis
            layered on it in a CLI session; its schedule is not stored, so this
            lists the hypotheses and does not draw them. ADR 0013. */}
        {whatIfs === null ? (
          <p className="text-muted">Could not read this draft's what-if session.</p>
        ) : whatIfs.length === 0 ? (
          <p className="text-muted">
            No what-ifs on this draft. Add them with <code>what-if</code> in the
            terminal; they belong to the draft, whoever types them.
          </p>
        ) : (
          <>
            <p className="text-muted">
              Hypotheses on this draft, in order. The grid above does not include
              them: a what-if changes what the scheduler is told, not what the
              draft holds, until <code>what-if apply</code> in the terminal.
              Discarding the draft discards these too.
            </p>
            <ol className="what-if-list" data-testid="what-ifs">
              {whatIfs.map((w, i) => (
                <li key={i}>{w.text}</li>
              ))}
            </ol>
          </>
        )}
      </div>

      {committing && (
        <CommitDraftDialog
          draft={draft}
          diff={diff ?? undefined}
          onClose={() => setCommitting(false)}
          onCommitted={(message) => {
            // The commit deleted this draft, so there is nothing left to show
            // here. The list gets the confirmation instead.
            navigate("/drafts", { replace: true, state: { message } });
          }}
        />
      )}
    </div>
  );
}
