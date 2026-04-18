import { useState, useEffect, useCallback } from "react";
import { useParams, Link } from "react-router";
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
  skillId: number,
  direct: Record<number, number[]>
): Set<number> {
  const result = new Set(direct[skillId] || []);
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
  const { id } = useParams<{ id: string }>();
  const skillId = Number(id);

  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [implications, setImplications] = useState<Record<number, number[]>>(
    {}
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Name editing
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState("");

  // Implication toggling
  const [toggling, setToggling] = useState<number | null>(null);

  const loadData = useCallback(async () => {
    try {
      const [sk, impl] = await Promise.all([
        fetchSkills(),
        fetchImplications(),
      ]);
      setSkills(sk);
      setImplications(impl);
      const current = sk.find((s) => s.id === skillId);
      if (current) setName(current.name);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [skillId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useEntityEvents("skill", loadData);

  if (loading) return <div className="page loading">Loading...</div>;
  if (error) return <div className="page msg-error">{error}</div>;

  const skill = skills.find((s) => s.id === skillId);
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

  const nameById: Record<number, string> = {};
  for (const s of skills) nameById[s.id] = s.name;

  const directImplications = new Set(implications[skillId] || []);
  const effective = effectiveSkills(skillId, implications);
  const otherSkills = skills.filter((s) => s.id !== skillId);

  async function handleSave() {
    setSaving(true);
    setSaveMsg("");
    try {
      await renameSkill(skillId, name);
      setSaveMsg("Saved");
      await loadData();
      setTimeout(() => setSaveMsg(""), 2000);
    } catch (err) {
      setSaveMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  async function handleToggle(targetId: number, checked: boolean) {
    setToggling(targetId);
    try {
      if (checked) {
        await addImplication(skillId, targetId);
      } else {
        await removeImplication(skillId, targetId);
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
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={saving}
          />
          <button
            className="btn"
            onClick={handleSave}
            disabled={saving || name === skill.name || !name.trim()}
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
              <label key={s.id} className="checkbox-label">
                <input
                  type="checkbox"
                  checked={directImplications.has(s.id)}
                  onChange={(e) => handleToggle(s.id, e.target.checked)}
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
            {[...effective]
              .map((id) => nameById[id] || `#${id}`)
              .join(", ")}
          </p>
        )}
      </div>
    </div>
  );
}
