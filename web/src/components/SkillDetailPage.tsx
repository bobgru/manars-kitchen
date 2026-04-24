import { useState, useEffect, useCallback } from "react";
import { useParams, Link, useNavigate } from "react-router";
import {
  fetchSkills,
  fetchImplications,
  renameSkill,
  addImplication,
  removeImplication,
  type SkillInfo,
} from "../api/skills";
import { useEntityEvents } from "../hooks/useSSE";

/** Compute transitive closure for a single skill. */
function effectiveSkills(
  skillName: string,
  direct: Record<string, string[]>
): Set<string> {
  const result = new Set(direct[skillName] || []);
  let changed = true;
  while (changed) {
    changed = false;
    for (const sk of [...result]) {
      for (const t of direct[sk] || []) {
        if (!result.has(t)) {
          result.add(t);
          changed = true;
        }
      }
    }
  }
  return result;
}

export default function SkillDetailPage() {
  const { name: urlName } = useParams<{ name: string }>();
  const decodedName = decodeURIComponent(urlName || "");
  const navigate = useNavigate();

  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [implications, setImplications] = useState<Record<string, string[]>>(
    {}
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Name editing
  const [editName, setEditName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");

  // Implication toggling
  const [toggling, setToggling] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    try {
      const [sk, impl] = await Promise.all([
        fetchSkills(),
        fetchImplications(),
      ]);
      setSkills(sk);
      setImplications(impl);
      const current = sk.find((s) => s.name.toLowerCase() === decodedName.toLowerCase());
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

  useEntityEvents("skill", loadData);

  if (loading) return <div className="page loading">Loading...</div>;
  if (error) return <div className="page msg-error">{error}</div>;

  const skill = skills.find((s) => s.name.toLowerCase() === decodedName.toLowerCase());
  if (!skill) {
    return (
      <div className="page">
        <Link to="/skills" className="back-link">
          &larr; Back to Skills
        </Link>
        <p className="msg-error">Skill not found.</p>
      </div>
    );
  }

  const directImplications = new Set(implications[skill.name] || []);
  const effective = effectiveSkills(skill.name, implications);
  const otherSkills = skills.filter((s) => s.name !== skill.name);

  async function handleSave() {
    setSaving(true);
    setSaveMsg("");
    try {
      await renameSkill(skill!.name, editName);
      setSaveMsg("Saved");
      navigate(`/skills/${encodeURIComponent(editName)}`, { replace: true });
      await loadData();
      setTimeout(() => setSaveMsg(""), 2000);
    } catch (err) {
      setSaveMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  async function handleToggle(targetName: string, checked: boolean) {
    setToggling(targetName);
    try {
      if (checked) {
        await addImplication(skill!.name, targetName);
      } else {
        await removeImplication(skill!.name, targetName);
      }
      await loadData();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setToggling(null);
    }
  }

  return (
    <div className="page">
      <Link to="/skills" className="back-link">
        &larr; Back to Skills
      </Link>
      <h2>Skill: {skill.name}</h2>

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
            disabled={saving || editName === skill.name || !editName.trim()}
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
        <h3>Implies</h3>
        {otherSkills.length === 0 ? (
          <p className="text-muted">No other skills to imply.</p>
        ) : (
          <div className="checkbox-group">
            {otherSkills.map((s) => (
              <label key={s.name} className="checkbox-label">
                <input
                  type="checkbox"
                  checked={directImplications.has(s.name)}
                  onChange={(e) => handleToggle(s.name, e.target.checked)}
                  disabled={toggling !== null}
                />
                {s.name}
              </label>
            ))}
          </div>
        )}
        {effective.size > 0 && (
          <p className="effective-skills">
            Effective skills:{" "}
            {[...effective].join(", ")}
          </p>
        )}
      </div>
    </div>
  );
}
