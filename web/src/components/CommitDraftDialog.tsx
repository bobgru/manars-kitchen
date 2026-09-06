import { useState } from "react";
import {
  commitDraft,
  forceCommitDraft,
  type DraftInfo,
  type OverlappingDrafts,
} from "../api/drafts";

interface Props {
  draft: DraftInfo;
  onClose: () => void;
  /**
   * Called once the commit lands. The draft no longer exists at this point, so a
   * caller showing the draft itself has to navigate away.
   */
  onCommitted: (message: string) => void;
}

/**
 * The commit flow: a note prompt, then the overlapping-drafts 409 and its force
 * override.
 *
 * Shared because it is a two-step refusal rather than a single confirm, and both
 * the drafts list and a draft's own page offer it. The three existing list/detail
 * pairs drifted apart in roughly ten ways by duplicating smaller things than
 * this.
 *
 * Errors render inside the dialog rather than being handed back to the page, so
 * that a failed commit leaves the note typed and the dialog open to retry.
 */
export default function CommitDraftDialog({ draft, onClose, onCommitted }: Props) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [conflict, setConflict] = useState<null | OverlappingDrafts>(null);

  async function handleCommit() {
    setBusy(true);
    setError("");
    try {
      const result = await commitDraft(draft.id, note);
      if (result.ok) {
        onCommitted(`Committed draft #${draft.id} to the calendar.`);
      } else {
        setConflict(result.overlapping);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function handleForceCommit() {
    setBusy(true);
    setError("");
    try {
      await forceCommitDraft(draft.id, note);
      onCommitted(
        `Committed draft #${draft.id}, replacing the overlapping dates.`
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  if (conflict) {
    return (
      <div className="modal-overlay" onClick={onClose}>
        <div className="modal" onClick={(e) => e.stopPropagation()}>
          <h3>Other drafts cover these dates</h3>
          <p>
            Committing draft #{draft.id} would overwrite the calendar for dates
            these drafts also claim:
          </p>
          <ul>
            {conflict.drafts.map((d) => (
              <li key={d.id}>
                draft #{d.id}, {d.dateFrom} to {d.dateTo}
              </li>
            ))}
          </ul>
          <p>
            They are not discarded, and the assignments being replaced are
            snapshotted into calendar history, so this is recoverable.
          </p>
          {error && <p className="msg-error">{error}</p>}
          <div className="modal-actions">
            <button className="btn btn-secondary" onClick={onClose} disabled={busy}>
              Cancel
            </button>
            <button
              className="btn btn-danger"
              onClick={handleForceCommit}
              disabled={busy}
            >
              {busy ? "Committing..." : "Commit Anyway"}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Commit draft #{draft.id}?</h3>
        <p>
          This replaces the calendar for {draft.dateFrom} to {draft.dateTo}. The
          whole range is the claim: dates in range with no assignment are cleared,
          not skipped. What is there now is snapshotted into calendar history
          first.
        </p>
        <label>
          Note{" "}
          <input
            type="text"
            placeholder="What this commit is for"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            disabled={busy}
          />
        </label>
        {error && <p className="msg-error">{error}</p>}
        <div className="modal-actions">
          <button className="btn btn-secondary" onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button className="btn" onClick={handleCommit} disabled={busy}>
            {busy ? "Committing..." : "Commit"}
          </button>
        </div>
      </div>
    </div>
  );
}
