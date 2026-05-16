import { useState, useEffect, useCallback } from "react";
import { useParams, Link, useNavigate } from "react-router";
import {
  fetchStations,
  renameStation,
  type StationInfo,
} from "../api/stations";
import { useEntityEvents } from "../hooks/useSSE";

export default function StationDetailPage() {
  const { name: urlName } = useParams<{ name: string }>();
  const decodedName = decodeURIComponent(urlName || "");
  const navigate = useNavigate();

  const [stations, setStations] = useState<StationInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [editName, setEditName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");

  const loadData = useCallback(async () => {
    try {
      const sts = await fetchStations();
      setStations(sts);
      const current = sts.find(
        (s) => s.name.toLowerCase() === decodedName.toLowerCase()
      );
      if (current) setEditName(current.name);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [decodedName]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEntityEvents("station", loadData);

  if (loading) return <div className="page loading">Loading...</div>;
  if (error) return <div className="page msg-error">{error}</div>;

  const station = stations.find(
    (s) => s.name.toLowerCase() === decodedName.toLowerCase()
  );
  if (!station) {
    return (
      <div className="page">
        <Link to="/stations" className="back-link">
          &larr; Back to Stations
        </Link>
        <p className="msg-error">Station not found.</p>
      </div>
    );
  }

  async function handleSave() {
    setSaving(true);
    setSaveMsg("");
    try {
      await renameStation(station!.name, editName);
      setSaveMsg("Saved");
      navigate(`/stations/${encodeURIComponent(editName)}`, { replace: true });
      await loadData();
      setTimeout(() => setSaveMsg(""), 2000);
    } catch (err) {
      setSaveMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page">
      <Link to="/stations" className="back-link">
        &larr; Back to Stations
      </Link>
      <h2>Station: {station.name}</h2>

      <div className="detail-section">
        <h3>Name</h3>
        <div className="form-row">
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
            disabled={saving || editName === station.name || !editName.trim()}
          >
            {saving ? "Saving..." : "Save"}
          </button>
          {saveMsg && (
            <span
              className={
                saveMsg === "Saved" ? "msg-success" : "msg-error"
              }
            >
              {saveMsg}
            </span>
          )}
        </div>
      </div>

      <div className="detail-section">
        <h3>Staffing</h3>
        <p>Min staff: {station.minStaff}</p>
        <p>Max staff: {station.maxStaff}</p>
      </div>
    </div>
  );
}
