import { apiFetch } from "./client";

export interface SkillInfo {
  id: number;
  name: string;
  description: string;
}

export async function fetchSkills(): Promise<SkillInfo[]> {
  const resp = await apiFetch("/api/skills");
  if (!resp.ok) throw new Error(`Failed to fetch skills: ${resp.status}`);
  const pairs: [number, { name: string; description: string }][] =
    await resp.json();
  return pairs.map(([id, s]) => ({ id, name: s.name, description: s.description }));
}

export async function fetchImplications(): Promise<Record<number, number[]>> {
  const resp = await apiFetch("/api/skills/implications");
  if (!resp.ok) throw new Error(`Failed to fetch implications: ${resp.status}`);
  return resp.json();
}

export async function renameSkill(id: number, name: string): Promise<void> {
  const resp = await apiFetch(`/api/skills/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
  if (!resp.ok) throw new Error(`Failed to rename skill: ${resp.status}`);
}

export async function addImplication(
  skillId: number,
  impliesSkillId: number
): Promise<void> {
  const resp = await apiFetch(`/api/skills/${skillId}/implications`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ impliesSkillId }),
  });
  if (!resp.ok) throw new Error(`Failed to add implication: ${resp.status}`);
}

export async function removeImplication(
  skillId: number,
  impliedId: number
): Promise<void> {
  const resp = await apiFetch(
    `/api/skills/${skillId}/implications/${impliedId}`,
    { method: "DELETE" }
  );
  if (!resp.ok) throw new Error(`Failed to remove implication: ${resp.status}`);
}
