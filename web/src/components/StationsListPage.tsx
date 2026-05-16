import { useState, useEffect, useCallback } from "react";
import { Link } from "react-router";
import {
  fetchStations,
  createStation,
  deleteStation,
  forceDeleteStation,
  type StationInfo,
  type StationReferences,
} from "../api/stations";
import { useEntityEvents } from "../hooks/useSSE";

export default function StationsListPage() {
  const [stations, setStations] = useState<StationInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [createError, setCreateError] = useState("");

  const [deleteConfirm, setDeleteConfirm] = useState<{
    stationName: string;
    refs: StationReferences;
  } | null>(null);

  const load = useCallback(async () => {
    try {
      const sts = await fetchStations();
      setStations(sts);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  useEntityEvents("station", load);

  if (loading) return <div className="page loading">Loading stations...</div>;
  if (error) return <div className="page msg-error">{error}</div>;

  async function handleCreate() {
    setCreateError("");
    if (!newName.trim()) {
      setCreateError("Name is required.");
      return;
    }
    try {
      await createStation(newName.trim());
      setShowCreate(false);
      setNewName("");
      load();
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleDelete(station: StationInfo) {
    try {
      const result = await deleteStation(station.name);
      if (result.ok) {
        load();
      } else {
        setDeleteConfirm({
          stationName: station.name,
          refs: result.references,
        });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleForceDelete() {
    if (!deleteConfirm) return;
    try {
      await forceDeleteStation(deleteConfirm.stationName);
      setDeleteConfirm(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  function renderRefs(refs: StationReferences) {
    const lines: string[] = [];
    for (const w of refs.workerPrefs) lines.push(`Worker preference: ${w.name}`);
    for (const s of refs.requiredSkills) lines.push(`Required skill: ${s.name}`);
    return lines;
  }

  return (
    <div className="page">
      <h2>Stations</h2>
      {!showCreate && (
        <button className="btn" onClick={() => setShowCreate(true)}>
          New Station
        </button>
      )}
      {showCreate && (
        <div className="inline-form">
          <input
            type="text"
            placeholder="Name"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
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
      {stations.length === 0 ? (
        <p className="text-muted">No stations defined.</p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Min Staff</th>
              <th>Max Staff</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {stations.map((s) => (
              <tr key={s.name}>
                <td>
                  <Link to={`/stations/${encodeURIComponent(s.name)}`}>{s.name}</Link>
                </td>
                <td>{s.minStaff}</td>
                <td>{s.maxStaff}</td>
                <td>
                  <button
                    className="btn btn-danger btn-sm"
                    onClick={() => handleDelete(s)}
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
            <h3>Cannot delete "{deleteConfirm.stationName}"</h3>
            <p>This station is still referenced:</p>
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
              <button className="btn btn-danger" onClick={handleForceDelete}>
                Force Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
