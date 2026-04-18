import { useState, useEffect, useCallback } from "react";
import { Link } from "react-router";
import { fetchSkills, fetchImplications, type SkillInfo } from "../api/skills";
import { useEntityEvents } from "../hooks/useSSE";

/** Compute transitive closure from a direct implications map. */
function transitiveClosure(
  direct: Record<number, number[]>
): Record<number, Set<number>> {
  const result: Record<number, Set<number>> = {};
  for (const [id, implied] of Object.entries(direct)) {
    result[Number(id)] = new Set(implied);
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const [id, skills] of Object.entries(result)) {
      for (const sk of [...skills]) {
        const transitive = result[sk];
        if (transitive) {
          for (const t of transitive) {
            if (!result[Number(id)].has(t)) {
              result[Number(id)].add(t);
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
  const [implications, setImplications] = useState<Record<number, number[]>>(
    {}
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

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

  const nameById: Record<number, string> = {};
  for (const s of skills) nameById[s.id] = s.name;

  const closure = transitiveClosure(implications);

  function renderImplications(skillId: number) {
    const direct = implications[skillId] || [];
    if (direct.length === 0) return <span className="text-muted">(none)</span>;

    const directSet = new Set(direct);
    const allImplied = closure[skillId] || new Set<number>();
    const transitiveOnly = [...allImplied].filter((id) => !directSet.has(id));

    return (
      <>
        <span className="impl-direct">
          {direct.map((id) => nameById[id] || `#${id}`).join(", ")}
        </span>
        {transitiveOnly.length > 0 && (
          <span className="impl-transitive">
            {" "}
            ({transitiveOnly.map((id) => nameById[id] || `#${id}`).join(", ")})
          </span>
        )}
      </>
    );
  }

  return (
    <div className="page">
      <h2>Skills</h2>
      {skills.length === 0 ? (
        <p className="text-muted">No skills defined.</p>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Implies</th>
            </tr>
          </thead>
          <tbody>
            {skills.map((s) => (
              <tr key={s.id}>
                <td>
                  <Link to={`/skills/${s.id}`}>{s.name}</Link>
                </td>
                <td>{renderImplications(s.id)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
