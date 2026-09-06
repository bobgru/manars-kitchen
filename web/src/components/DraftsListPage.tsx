import { useState, useEffect, useCallback } from "react";
import {
  fetchDrafts,
  fetchDraftAssignments,
  createDraft,
  generateDraft,
  commitDraft,
  forceCommitDraft,
  discardDraft,
  type DraftInfo,
  type DraftAssignments,
  type FrozenDates,
  type OverlappingDrafts,
} from "../api/drafts";
import { useEntityEvents } from "../hooks/useSSE";

/**
 * A draft plus the summary read from `/api/drafts/:id/assignments`.
 *
 * `detail` is null while it is still loading and stays null if that one request
 * failed, so a single bad row degrades to just its metadata rather than taking
 * the page down with it. This is one request per draft; drafts are few and
 * short-lived, and `/api/drafts` reports no counts of its own.
 */
interface DraftRow {
  draft: DraftInfo;
  detail: DraftAssignments | null;
}

function describeCommit(c: { draftId: number | null; id: number; note: string }): string {
  if (c.draftId !== null) return `draft #${c.draftId}`;
  return c.note ? `commit #${c.id} (${c.note})` : `commit #${c.id}`;
}

export default function DraftsListPage() {
  const [rows, setRows] = useState<DraftRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [toast, setToast] = useState("");

  const [showCreate, setShowCreate] = useState(false);
  const [createFrom, setCreateFrom] = useState("");
  const [createTo, setCreateTo] = useState("");
  const [createError, setCreateError] = useState("");
  const [frozenRefusal, setFrozenRefusal] = useState<null | FrozenDates>(null);

  /** The draft whose id is here has a request in flight; its buttons are off. */
  const [busyId, setBusyId] = useState<number | null>(null);

  const [commitPrompt, setCommitPrompt] = useState<null | { draft: DraftInfo }>(null);
  const [commitNote, setCommitNote] = useState("");
  const [commitConflict, setCommitConflict] = useState<null | {
    draft: DraftInfo;
    note: string;
    overlapping: OverlappingDrafts;
  }>(null);

  const [deleteConfirm, setDeleteConfirm] = useState<null | { draft: DraftInfo }>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      const drafts = await fetchDrafts();
      setRows(drafts.map((draft) => ({ draft, detail: null })));
      const details = await Promise.all(
        drafts.map((d) => fetchDraftAssignments(d.id).catch(() => null))
      );
      setRows(drafts.map((draft, i) => ({ draft, detail: details[i] })));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  useEntityEvents("draft", load);
  // A commit lands on the calendar, which is what makes other drafts' baselines
  // move; without this the "calendar replaced" warnings would go stale.
  useEntityEvents("calendar", load);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }

  function openCreate() {
    setShowCreate(true);
    setCreateFrom("");
    setCreateTo("");
    setCreateError("");
  }

  async function handleCreate() {
    setCreateError("");
    if (!createFrom || !createTo) {
      setCreateError("Both dates are required.");
      return;
    }
    if (createFrom > createTo) {
      setCreateError("The start date must not be after the end date.");
      return;
    }
    try {
      const result = await createDraft(createFrom, createTo);
      if (result.ok) {
        setShowCreate(false);
        showToast(`Created draft #${result.id}.`);
        load();
      } else {
        setFrozenRefusal(result.frozen);
      }
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleGenerate(draft: DraftInfo) {
    setBusyId(draft.id);
    try {
      const result = await generateDraft(draft.id);
      showToast(
        `Generated draft #${draft.id}: ${result.schedule.length} assignment(s), ` +
          `${result.unfilled.length} unfilled.`
      );
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusyId(null);
    }
  }

  function openCommit(draft: DraftInfo) {
    setCommitPrompt({ draft });
    setCommitNote("");
  }

  async function handleCommit() {
    if (!commitPrompt) return;
    const { draft } = commitPrompt;
    const note = commitNote;
    setBusyId(draft.id);
    try {
      const result = await commitDraft(draft.id, note);
      setCommitPrompt(null);
      if (result.ok) {
        showToast(`Committed draft #${draft.id} to the calendar.`);
        load();
      } else {
        setCommitConflict({ draft, note, overlapping: result.overlapping });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusyId(null);
    }
  }

  async function handleForceCommit() {
    if (!commitConflict) return;
    const { draft, note } = commitConflict;
    setBusyId(draft.id);
    try {
      await forceCommitDraft(draft.id, note);
      setCommitConflict(null);
      showToast(`Committed draft #${draft.id}, replacing the overlapping dates.`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusyId(null);
    }
  }

  async function handleDiscard() {
    if (!deleteConfirm) return;
    const { draft } = deleteConfirm;
    setBusyId(draft.id);
    try {
      await discardDraft(draft.id);
      setDeleteConfirm(null);
      showToast(`Discarded draft #${draft.id}.`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusyId(null);
    }
  }

  if (loading) return <div className="page loading">Loading drafts...</div>;

  return (
    <div className="page">
      <h2>Drafts</h2>

      {error && <div className="msg-error">{error}</div>}
      {toast && <div className="msg-success">{toast}</div>}

      {!showCreate && (
        <div className="action-bar">
          <button className="btn" onClick={openCreate}>
            New Draft
          </button>
        </div>
      )}
      {showCreate && (
        <div className="inline-form">
          <strong>New Draft</strong>
          <label>
            From{" "}
            <input
              type="date"
              value={createFrom}
              onChange={(e) => setCreateFrom(e.target.value)}
            />
          </label>
          <label>
            To{" "}
            <input
              type="date"
              value={createTo}
              onChange={(e) => setCreateTo(e.target.value)}
            />
          </label>
          <button className="btn" onClick={handleCreate}>
            Create
          </button>
          <button className="btn btn-secondary" onClick={() => setShowCreate(false)}>
            Cancel
          </button>
          {createError && <span className="msg-error">{createError}</span>}
        </div>
      )}

      {rows.length === 0 ? (
        <p className="text-muted">
          No drafts. A draft is a working copy of a date range you can generate
          into, then commit to the calendar.
        </p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Draft</th>
              <th>Date range</th>
              <th>Created</th>
              <th>Assignments</th>
              <th>State</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.map(({ draft, detail }) => (
              <tr key={draft.id}>
                <td>#{draft.id}</td>
                <td>
                  {draft.dateFrom} to {draft.dateTo}
                </td>
                <td>{draft.createdAt}</td>
                <td>{detail ? detail.assignments.length : "—"}</td>
                <td>
                  {/* Every state is spelled out in words. Nothing here is
                      distinguished by colour alone. */}
                  {detail === null && <span className="text-muted">not loaded</span>}
                  {detail !== null && detail.replacedUnder.length > 0 && (
                    <div className="msg-warn">
                      Warning: calendar replaced by{" "}
                      {detail.replacedUnder.map(describeCommit).join(", ")}
                    </div>
                  )}
                  {detail !== null && detail.violations.length > 0 && (
                    <div className="msg-error">
                      {detail.violations.length} violation(s):{" "}
                      {detail.violations.map((v) => v.constraint).join(", ")}
                    </div>
                  )}
                  {detail !== null &&
                    detail.replacedUnder.length === 0 &&
                    detail.violations.length === 0 && (
                      <span className="msg-success">OK</span>
                    )}
                </td>
                <td>
                  <button
                    className="btn btn-sm"
                    disabled={busyId === draft.id}
                    onClick={() => handleGenerate(draft)}
                  >
                    {busyId === draft.id ? "Working..." : "Generate"}
                  </button>
                  <button
                    className="btn btn-sm"
                    disabled={busyId === draft.id}
                    onClick={() => openCommit(draft)}
                  >
                    Commit
                  </button>
                  <button
                    className="btn btn-danger btn-sm"
                    disabled={busyId === draft.id}
                    onClick={() => setDeleteConfirm({ draft })}
                  >
                    Discard
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {frozenRefusal && (
        <div className="modal-overlay" onClick={() => setFrozenRefusal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>That range covers frozen dates</h3>
            <p>
              Dates {frozenRefusal.frozenFrom} to {frozenRefusal.frozenTo} are on or
              before the freeze line ({frozenRefusal.freezeLine}).
            </p>
            <p>
              There is no override here. Either pick a later range, or unfreeze the
              dates from the CLI first:
            </p>
            <pre>
              calendar unfreeze {frozenRefusal.frozenFrom} {frozenRefusal.frozenTo}
            </pre>
            <div className="modal-actions">
              <button className="btn" onClick={() => setFrozenRefusal(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {commitPrompt && (
        <div className="modal-overlay" onClick={() => setCommitPrompt(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Commit draft #{commitPrompt.draft.id}?</h3>
            <p>
              This replaces the calendar for {commitPrompt.draft.dateFrom} to{" "}
              {commitPrompt.draft.dateTo}. The whole range is the claim: dates in
              range with no assignment are cleared, not skipped. What is there now
              is snapshotted into calendar history first.
            </p>
            <label>
              Note{" "}
              <input
                type="text"
                placeholder="What this commit is for"
                value={commitNote}
                onChange={(e) => setCommitNote(e.target.value)}
              />
            </label>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setCommitPrompt(null)}
              >
                Cancel
              </button>
              <button className="btn" onClick={handleCommit}>
                Commit
              </button>
            </div>
          </div>
        </div>
      )}

      {commitConflict && (
        <div className="modal-overlay" onClick={() => setCommitConflict(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Other drafts cover these dates</h3>
            <p>
              Committing draft #{commitConflict.draft.id} would overwrite the
              calendar for dates these drafts also claim:
            </p>
            <ul>
              {commitConflict.overlapping.drafts.map((d) => (
                <li key={d.id}>
                  draft #{d.id}, {d.dateFrom} to {d.dateTo}
                </li>
              ))}
            </ul>
            <p>
              They are not discarded, and the assignments being replaced are
              snapshotted into calendar history, so this is recoverable.
            </p>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setCommitConflict(null)}
              >
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleForceCommit}>
                Commit Anyway
              </button>
            </div>
          </div>
        </div>
      )}

      {deleteConfirm && (
        <div className="modal-overlay" onClick={() => setDeleteConfirm(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Discard draft #{deleteConfirm.draft.id}?</h3>
            <p>
              Its assignments and any saved what-if session go with it. The
              calendar is not touched.
            </p>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setDeleteConfirm(null)}
              >
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleDiscard}>
                Discard
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
