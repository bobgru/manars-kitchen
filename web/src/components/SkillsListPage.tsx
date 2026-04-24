import { useState, useEffect, useCallback } from "react";
import { Link } from "react-router";
import {
  fetchSkills,
  fetchImplications,
  createSkill,
  deleteSkill,
  forceDeleteSkill,
  type SkillInfo,
  type SkillReferences,
} from "../api/skills";
import { useEntityEvents } from "../hooks/useSSE";

/** Compute transitive closure from a direct implications map. */
function transitiveClosure(
  direct: Record<string, string[]>
): Record<string, Set<string>> {
  const result: Record<string, Set<string>> = {};
  for (const [name, implied] of Object.entries(direct)) {
    result[name] = new Set(implied);
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, skills] of Object.entries(result)) {
      for (const sk of [...skills]) {
        const transitive = result[sk];
        if (transitive) {
          for (const t of transitive) {
            if (!result[name].has(t)) {
              result[name].add(t);
              changed = true;
            }
          }
        }
      }
    }
  }
  return result;
}

export default function SkillsListPage() {
  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [implications, setImplications] = useState<Record<string, string[]>>(
    {}
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [createError, setCreateError] = useState("");

  const [deleteConfirm, setDeleteConfirm] = useState<{
    skillName: string;
    refs: SkillReferences;
  } | null>(null);

  const load = useCallback(async () => {
    try {
      const [sk, impl] = await Promise.all([
        fetchSkills(),
        fetchImplications(),
      ]);
      setSkills(sk);
      setImplications(impl);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  useEntityEvents("skill", load);

  if (loading) return <div className="page loading">Loading skills...</div>;
  if (error) return <div className="page msg-error">{error}</div>;

  const closure = transitiveClosure(implications);

  function renderImplications(skillName: string) {
    const direct = implications[skillName] || [];
    if (direct.length === 0) return <span className="text-muted">(none)</span>;

    const directSet = new Set(direct);
    const allImplied = closure[skillName] || new Set<string>();
    const transitiveOnly = [...allImplied].filter((n) => !directSet.has(n));

    return (
      <>
        <span className="impl-direct">
          {direct.join(", ")}
        </span>
        {transitiveOnly.length > 0 && (
          <span className="impl-transitive">
            {" "}
            ({transitiveOnly.join(", ")})
          </span>
        )}
      </>
    );
  }

  async function handleCreate() {
    setCreateError("");
    if (!newName.trim()) {
      setCreateError("Name is required.");
      return;
    }
    try {
      await createSkill(newName.trim());
      setShowCreate(false);
      setNewName("");
      load();
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : String(err));
    }
  }

  async function handleDelete(skill: SkillInfo) {
    try {
      const result = await deleteSkill(skill.name);
      if (result.ok) {
        load();
      } else {
        setDeleteConfirm({
          skillName: skill.name,
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
      await forceDeleteSkill(deleteConfirm.skillName);
      setDeleteConfirm(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  function renderRefs(refs: SkillReferences) {
    const lines: string[] = [];
    for (const w of refs.workers) lines.push(`Worker: ${w.name}`);
    for (const s of refs.stations) lines.push(`Station: ${s.name}`);
    for (const w of refs.crossTraining) lines.push(`Cross-training: ${w.name}`);
    for (const s of refs.impliedBy) lines.push(`Implied by: ${s.name}`);
    for (const s of refs.implies) lines.push(`Implies: ${s.name}`);
    return lines;
  }

  return (
    <div className="page">
      <h2>Skills</h2>
      {!showCreate && (
        <button className="btn" onClick={() => setShowCreate(true)}>
          New Skill
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
      {skills.length === 0 ? (
        <p className="text-muted">No skills defined.</p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Implies</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {skills.map((s) => (
              <tr key={s.name}>
                <td>
                  <Link to={`/skills/${encodeURIComponent(s.name)}`}>{s.name}</Link>
                </td>
                <td>{renderImplications(s.name)}</td>
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
            <h3>Cannot delete "{deleteConfirm.skillName}"</h3>
            <p>This skill is still referenced:</p>
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
