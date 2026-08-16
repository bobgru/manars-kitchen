import { useState, useEffect, useCallback } from "react";
import {
  fetchShifts,
  createShift,
  deleteShift,
  type ShiftInfo,
} from "../api/shifts";
import { useEntityEvents } from "../hooks/useSSE";

/** Render an integer hour as a 24-hour clock time, e.g. 6 -> "06:00". */
function formatHour(hour: number): string {
  return `${String(hour).padStart(2, "0")}:00`;
}

/** Readable time range for a shift; end hour is exclusive. */
function formatRange(shift: ShiftInfo): string {
  return `${formatHour(shift.start)} - ${formatHour(shift.end)}`;
}

/** Parse an hour field, returning null when it is not an integer 0-24. */
function parseHour(raw: string): number | null {
  const trimmed = raw.trim();
  if (!/^\d+$/.test(trimmed)) return null;
  const hour = Number(trimmed);
  if (hour < 0 || hour > 24) return null;
  return hour;
}

export default function ShiftsListPage() {
  const [shifts, setShifts] = useState<ShiftInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [toast, setToast] = useState("");

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [newStart, setNewStart] = useState("");
  const [newEnd, setNewEnd] = useState("");
  const [createError, setCreateError] = useState("");

  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      const list = await fetchShifts();
      setShifts(list);
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

  useEntityEvents("shift", load);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }

  function openCreate() {
    setShowCreate(true);
    setNewName("");
    setNewStart("");
    setNewEnd("");
    setCreateError("");
  }

  async function handleCreate() {
    setCreateError("");
    if (!newName.trim()) {
      setCreateError("Name is required.");
      return;
    }
    const start = parseHour(newStart);
    const end = parseHour(newEnd);
    if (start === null || end === null) {
      setCreateError("Start and end must be whole hours between 0 and 24.");
      return;
    }
    if (start >= end) {
      setCreateError("Start hour must be before end hour.");
      return;
    }
    try {
      await createShift(newName.trim(), start, end);
      setShowCreate(false);
      showToast(`Created shift ${newName.trim()}.`);
      load();
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleConfirmDelete() {
    if (!deleteConfirm) return;
    try {
      await deleteShift(deleteConfirm);
      showToast(`Deleted shift ${deleteConfirm}.`);
      setDeleteConfirm(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  if (loading) return <div className="page loading">Loading shifts...</div>;

  return (
    <div className="page">
      <h2>Shifts</h2>

      {error && <div className="msg-error">{error}</div>}
      {toast && <div className="msg-success">{toast}</div>}

      {!showCreate && (
        <div className="action-bar">
          <button className="btn" onClick={openCreate}>
            New Shift
          </button>
        </div>
      )}
      {showCreate && (
        <div className="inline-form">
          <input
            type="text"
            placeholder="Name"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
          />
          <input
            type="text"
            placeholder="Start hour"
            value={newStart}
            onChange={(e) => setNewStart(e.target.value)}
          />
          <input
            type="text"
            placeholder="End hour"
            value={newEnd}
            onChange={(e) => setNewEnd(e.target.value)}
          />
          <button className="btn" onClick={handleCreate}>
            Create
          </button>
          <button
            className="btn btn-secondary"
            onClick={() => {
              setShowCreate(false);
              setCreateError("");
            }}
          >
            Cancel
          </button>
          {createError && <span className="msg-error">{createError}</span>}
        </div>
      )}

      {shifts.length === 0 ? (
        <p className="text-muted">No shifts defined.</p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Start</th>
              <th>End</th>
              <th>Hours</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {shifts.map((s) => (
              <tr key={s.name}>
                <td>{s.name}</td>
                <td>{s.start}</td>
                <td>{s.end}</td>
                <td>{formatRange(s)}</td>
                <td>
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => setDeleteConfirm(s.name)}
                  >
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {deleteConfirm && (
        <div className="modal-overlay" onClick={() => setDeleteConfirm(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Delete "{deleteConfirm}"?</h3>
            <p>
              This removes the shift definition. Worker shift preferences
              naming it are left in place and will no longer match anything.
            </p>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setDeleteConfirm(null)}
              >
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleConfirmDelete}>
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
