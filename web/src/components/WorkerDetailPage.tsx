import { useState, useEffect, useCallback } from "react";
import { useParams, Link, useNavigate } from "react-router";
import {
  fetchWorkerProfile,
  renameWorker,
  deactivateWorker,
  forceDeactivateWorker,
  activateWorker,
  type WorkerProfile,
  type DeactivationImpact,
} from "../api/workers";
import { useEntityEvents, type SSEEvent } from "../hooks/useSSE";

/**
 * Tokenize a command string respecting "double" and 'single' quotes.
 * Mirrors the server's shellWords lenient behavior. Returns [] if input
 * is empty or unparseable.
 */
function shellWords(input: string): string[] {
  const tokens: string[] = [];
  let i = 0;
  while (i < input.length) {
    while (i < input.length && /\s/.test(input[i])) i++;
    if (i >= input.length) break;
    let token = "";
    if (input[i] === '"' || input[i] === "'") {
      const quote = input[i];
      i++;
      while (i < input.length && input[i] !== quote) {
        if (input[i] === "\\" && i + 1 < input.length) {
          token += input[i + 1];
          i += 2;
        } else {
          token += input[i];
          i++;
        }
      }
      if (i < input.length) i++; // skip closing quote
    } else {
      while (i < input.length && !/\s/.test(input[i])) {
        token += input[i];
        i++;
      }
    }
    tokens.push(token);
  }
  return tokens;
}

/** If command is `user rename <old> <new>`, return [old, new]; else null. */
function parseUserRename(command: string): [string, string] | null {
  const parts = shellWords(command);
  if (parts.length >= 4 && parts[0] === "user" && parts[1] === "rename") {
    return [parts[2], parts[3]];
  }
  return null;
}

export default function WorkerDetailPage() {
  const { name: urlName } = useParams<{ name: string }>();
  const decodedName = decodeURIComponent(urlName || "");
  const navigate = useNavigate();

  const [profile, setProfile] = useState<WorkerProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState("");
  const [toast, setToast] = useState("");

  const [editName, setEditName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");

  const [deactivatePreview, setDeactivatePreview] = useState<null | DeactivationImpact>(
    null
  );

  const loadData = useCallback(async () => {
    try {
      setError("");
      setNotFound(false);
      const p = await fetchWorkerProfile(decodedName);
      setProfile(p);
      setEditName(p.name);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("404")) {
        setNotFound(true);
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  }, [decodedName]);

  useEffect(() => {
    setLoading(true);
    loadData();
  }, [loadData]);

  const handleUserEvent = useCallback(
    (event: SSEEvent) => {
      const renamed = parseUserRename(event.command);
      if (renamed && renamed[0] === decodedName) {
        navigate(`/workers/${encodeURIComponent(renamed[1])}`, { replace: true });
        return;
      }
      loadData();
    },
    [decodedName, navigate, loadData]
  );

  useEntityEvents("worker", loadData);
  useEntityEvents("user", handleUserEvent);

  function showToast(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }

  async function handleSave() {
    if (!profile) return;
    setSaving(true);
    setSaveMsg("");
    try {
      await renameWorker(profile.name, editName);
      setSaveMsg("Saved");
      navigate(`/workers/${encodeURIComponent(editName)}`, { replace: true });
      setTimeout(() => setSaveMsg(""), 2000);
    } catch (err) {
      setSaveMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  async function handleDeactivate() {
    if (!profile) return;
    try {
      const result = await deactivateWorker(profile.name);
      if (result.ok) {
        showToast(`Deactivated ${profile.name}.`);
        loadData();
      } else {
        setDeactivatePreview(result.impact);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleConfirmForceDeactivate() {
    if (!profile) return;
    try {
      const impact = await forceDeactivateWorker(profile.name);
      const total = impact.pinsRemoved + impact.draftsRemoved + impact.calendarRemoved;
      showToast(`Deactivated ${profile.name}. Removed ${total} reference(s).`);
      setDeactivatePreview(null);
      loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleActivate() {
    if (!profile) return;
    try {
      await activateWorker(profile.name);
      showToast(`Activated ${profile.name}.`);
      loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  if (loading) return <div className="page loading">Loading worker...</div>;
  if (notFound) {
    return (
      <div className="page">
        <Link to="/workers" className="back-link">
          &larr; Back to Workers
        </Link>
        <p className="msg-error">Worker not found.</p>
      </div>
    );
  }
  if (!profile) {
    return (
      <div className="page msg-error">{error || "Failed to load worker."}</div>
    );
  }

  return (
    <div className="page">
      <Link to="/workers" className="back-link">
        &larr; Back to Workers
      </Link>
      <h2>Worker: {profile.name}</h2>

      {error && <div className="msg-error">{error}</div>}
      {toast && <div className="msg-success">{toast}</div>}

      <div className="detail-section">
        <h3>Identity</h3>
        <div className="form-row">
          <label>Name:</label>
          <input
            className="form-input"
            type="text"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            disabled={saving}
          />
          <button
            className="btn"
            onClick={handleSave}
            disabled={saving || editName === profile.name || !editName.trim()}
          >
            {saving ? "Saving..." : "Save"}
          </button>
          {saveMsg && (
            <span className={saveMsg === "Saved" ? "msg-success" : "msg-error"}>
              {saveMsg}
            </span>
          )}
        </div>
        <div className="form-row">
          <label>Status:</label>
          <span>{profile.status}</span>
          {profile.status === "active" && (
            <button className="btn btn-sm" onClick={handleDeactivate}>
              Deactivate
            </button>
          )}
          {profile.status === "inactive" && (
            <button className="btn btn-sm" onClick={handleActivate}>
              Activate
            </button>
          )}
        </div>
        <div className="form-row">
          <label>Role:</label>
          <span>{profile.role}</span>
        </div>
        <div className="form-row">
          <label>User ID:</label>
          <span>{profile.userId}</span>
        </div>
        <div className="form-row">
          <label>Worker ID:</label>
          <span>{profile.workerId}</span>
        </div>
      </div>

      <div className="detail-section">
        <h3>Skills ({profile.skills.length}) — managed via CLI for now</h3>
        <p>{profile.skills.length === 0 ? "(none)" : profile.skills.join(", ")}</p>
      </div>

      <div className="detail-section">
        <h3>Employment — managed via CLI for now</h3>
        <ul>
          <li>Overtime model: {profile.overtimeModel}</li>
          <li>Pay period tracking: {profile.payPeriodTracking}</li>
          <li>Temp: {profile.isTemp ? "yes" : "no"}</li>
          <li>
            Max period hours:{" "}
            {profile.maxPeriodHours == null ? "(unset)" : `${profile.maxPeriodHours}h`}
          </li>
          <li>Overtime opt-in: {profile.overtimeOptIn ? "yes" : "no"}</li>
        </ul>
      </div>

      <div className="detail-section">
        <h3>Preferences — managed via CLI for now</h3>
        <ul>
          <li>Weekend-only: {profile.weekendOnly ? "yes" : "no"}</li>
          <li>Prefers variety: {profile.prefersVariety ? "yes" : "no"}</li>
          <li>Seniority: {profile.seniority}</li>
          <li>
            Shift prefs:{" "}
            {profile.shiftPrefs.length === 0 ? "(none)" : profile.shiftPrefs.join(", ")}
          </li>
        </ul>
      </div>

      <div className="detail-section">
        <h3>Station Prefs ({profile.stationPrefs.length}) — managed via CLI for now</h3>
        <p>
          {profile.stationPrefs.length === 0
            ? "(none)"
            : profile.stationPrefs.join(", ")}
        </p>
      </div>

      <div className="detail-section">
        <h3>
          Cross-training ({profile.crossTraining.length}) — managed via CLI for now
        </h3>
        <p>
          {profile.crossTraining.length === 0
            ? "(none)"
            : profile.crossTraining.join(", ")}
        </p>
      </div>

      <div className="detail-section">
        <h3>Pairing — managed via CLI for now</h3>
        <ul>
          <li>
            Avoid:{" "}
            {profile.avoidPairing.length === 0
              ? "(none)"
              : profile.avoidPairing.join(", ")}
          </li>
          <li>
            Prefer:{" "}
            {profile.preferPairing.length === 0
              ? "(none)"
              : profile.preferPairing.join(", ")}
          </li>
        </ul>
      </div>

      {deactivatePreview && (
        <div className="modal-overlay" onClick={() => setDeactivatePreview(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Deactivate "{profile.name}"?</h3>
            <p>The following references will be removed:</p>
            <ul>
              <li>{deactivatePreview.pinsRemoved} pinned assignment(s)</li>
              <li>{deactivatePreview.draftsRemoved} draft entry(ies)</li>
              <li>{deactivatePreview.calendarRemoved} future calendar slot(s)</li>
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
    </div>
  );
}
