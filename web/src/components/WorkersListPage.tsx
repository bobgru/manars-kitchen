import { useState, useEffect, useCallback } from "react";
import { Link, useSearchParams } from "react-router";
import {
  fetchWorkers,
  deactivateWorker,
  forceDeactivateWorker,
  activateWorker,
  deleteWorker,
  forceDeleteWorker,
  createUser,
  type WorkerSummary,
  type StatusFilter,
  type DeactivationImpact,
  type WorkerReferences,
} from "../api/workers";
import { useEntityEvents } from "../hooks/useSSE";

function isStatusFilter(s: string | null): s is StatusFilter {
  return s === "active" || s === "inactive" || s === "all";
}

export default function WorkersListPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const rawStatus = searchParams.get("status");
  const status: StatusFilter = isStatusFilter(rawStatus) ? rawStatus : "active";

  const [workers, setWorkers] = useState<WorkerSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [toast, setToast] = useState("");

  const [showCreate, setShowCreate] = useState<null | { noWorker: boolean }>(null);
  const [createName, setCreateName] = useState("");
  const [createPassword, setCreatePassword] = useState("");
  const [createRole, setCreateRole] = useState("normal");
  const [createError, setCreateError] = useState("");

  const [deactivatePreview, setDeactivatePreview] = useState<null | {
    name: string;
    impact: DeactivationImpact;
  }>(null);

  const [deleteConfirm, setDeleteConfirm] = useState<null | {
    name: string;
    refs: WorkerReferences;
  }>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      const list = await fetchWorkers(status);
      setWorkers(list);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  useEntityEvents("worker", load);
  useEntityEvents("user", load);

  function changeFilter(next: StatusFilter) {
    setSearchParams({ status: next });
  }

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }

  async function handleDeactivate(w: WorkerSummary) {
    try {
      const result = await deactivateWorker(w.name);
      if (result.ok) {
        showToast(`Deactivated ${w.name}.`);
        load();
      } else {
        setDeactivatePreview({ name: w.name, impact: result.impact });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleConfirmForceDeactivate() {
    if (!deactivatePreview) return;
    try {
      const impact = await forceDeactivateWorker(deactivatePreview.name);
      const total = impact.pinsRemoved + impact.draftsRemoved + impact.calendarRemoved;
      showToast(`Deactivated ${deactivatePreview.name}. Removed ${total} reference(s).`);
      setDeactivatePreview(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleActivate(w: WorkerSummary) {
    try {
      await activateWorker(w.name);
      showToast(`Activated ${w.name}.`);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleDelete(w: WorkerSummary) {
    try {
      const result = await deleteWorker(w.name);
      if (result.ok) {
        showToast(`Deleted worker concept for ${w.name}.`);
        load();
      } else {
        setDeleteConfirm({ name: w.name, refs: result.references });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleConfirmForceDelete() {
    if (!deleteConfirm) return;
    try {
      await forceDeleteWorker(deleteConfirm.name);
      showToast(`Force-deleted worker ${deleteConfirm.name}.`);
      setDeleteConfirm(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  function openCreate(noWorker: boolean) {
    setShowCreate({ noWorker });
    setCreateName("");
    setCreatePassword("");
    setCreateRole("normal");
    setCreateError("");
  }

  async function handleCreate() {
    if (!showCreate) return;
    setCreateError("");
    if (!createName.trim() || !createPassword.trim()) {
      setCreateError("Username and password are required.");
      return;
    }
    try {
      await createUser({
        username: createName.trim(),
        password: createPassword,
        role: createRole,
        noWorker: showCreate.noWorker,
      });
      setShowCreate(null);
      load();
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : String(err));
    }
  }

  function renderRefs(refs: WorkerReferences) {
    const lines: string[] = [];
    for (const c of refs.configuration) lines.push(`Configuration: ${c}`);
    for (const s of refs.schedule) lines.push(`Schedule: ${s}`);
    return lines;
  }

  if (loading) return <div className="page loading">Loading workers...</div>;

  return (
    <div className="page">
      <h2>Workers</h2>

      {error && <div className="msg-error">{error}</div>}
      {toast && <div className="msg-success">{toast}</div>}

      <div className="filter-bar">
        <label>
          Filter:{" "}
          <select
            value={status}
            onChange={(e) => changeFilter(e.target.value as StatusFilter)}
          >
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="all">All</option>
          </select>
        </label>
      </div>

      {!showCreate && (
        <div className="action-bar">
          <button className="btn" onClick={() => openCreate(false)}>
            New Worker
          </button>
          <button className="btn btn-secondary" onClick={() => openCreate(true)}>
            New User (no worker)
          </button>
        </div>
      )}
      {showCreate && (
        <div className="inline-form">
          <strong>{showCreate.noWorker ? "New User (no worker)" : "New Worker"}</strong>
          <input
            type="text"
            placeholder="Username"
            value={createName}
            onChange={(e) => setCreateName(e.target.value)}
          />
          <input
            type="password"
            placeholder="Password"
            value={createPassword}
            onChange={(e) => setCreatePassword(e.target.value)}
          />
          <select value={createRole} onChange={(e) => setCreateRole(e.target.value)}>
            <option value="normal">normal</option>
            <option value="admin">admin</option>
          </select>
          <button className="btn" onClick={handleCreate}>
            Create
          </button>
          <button className="btn btn-secondary" onClick={() => setShowCreate(null)}>
            Cancel
          </button>
          {createError && <span className="msg-error">{createError}</span>}
        </div>
      )}

      {workers.length === 0 ? (
        <p className="text-muted">No workers match filter "{status}".</p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Role</th>
              <th>Status</th>
              <th>Temp</th>
              <th>Weekend-only</th>
              <th>Seniority</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {workers.map((w) => (
              <tr key={w.name}>
                <td>
                  <Link to={`/workers/${encodeURIComponent(w.name)}`}>{w.name}</Link>
                </td>
                <td>{w.role}</td>
                <td>{w.status}</td>
                <td>{w.isTemp ? "yes" : "no"}</td>
                <td>{w.weekendOnly ? "yes" : "no"}</td>
                <td>{w.seniority}</td>
                <td>
                  {w.status === "active" && (
                    <button
                      className="btn btn-sm"
                      onClick={() => handleDeactivate(w)}
                    >
                      Deactivate
                    </button>
                  )}
                  {w.status === "inactive" && (
                    <button
                      className="btn btn-sm"
                      onClick={() => handleActivate(w)}
                    >
                      Activate
                    </button>
                  )}
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => handleDelete(w)}
                  >
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {deactivatePreview && (
        <div
          className="modal-overlay"
          onClick={() => setDeactivatePreview(null)}
        >
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Deactivate "{deactivatePreview.name}"?</h3>
            <p>The following references will be removed:</p>
            <ul>
              <li>{deactivatePreview.impact.pinsRemoved} pinned assignment(s)</li>
              <li>{deactivatePreview.impact.draftsRemoved} draft entry(ies)</li>
              <li>
                {deactivatePreview.impact.calendarRemoved} future calendar slot(s)
              </li>
            </ul>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setDeactivatePreview(null)}
              >
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleConfirmForceDeactivate}>
                Deactivate Anyway
              </button>
            </div>
          </div>
        </div>
      )}

      {deleteConfirm && (
        <div className="modal-overlay" onClick={() => setDeleteConfirm(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Cannot delete "{deleteConfirm.name}"</h3>
            <p>This worker is still referenced:</p>
            <ul>
              {renderRefs(deleteConfirm.refs).map((line, i) => (
                <li key={i}>{line}</li>
              ))}
            </ul>
            <p>Force delete will remove all references first.</p>
            <div className="modal-actions">
              <button
                className="btn btn-secondary"
                onClick={() => setDeleteConfirm(null)}
              >
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleConfirmForceDelete}>
                Force Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
