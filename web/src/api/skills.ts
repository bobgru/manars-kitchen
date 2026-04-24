import { apiFetch } from "./client";

export interface SkillInfo {
  name: string;
  description: string;
}

export async function fetchSkills(): Promise<SkillInfo[]> {
  const resp = await apiFetch("/api/skills");
  if (!resp.ok) throw new Error(`Failed to fetch skills: ${resp.status}`);
  return resp.json();
}

export async function fetchImplications(): Promise<Record<string, string[]>> {
  const resp = await apiFetch("/api/skills/implications");
  if (!resp.ok) throw new Error(`Failed to fetch implications: ${resp.status}`);
  return resp.json();
}

export async function createSkill(
  name: string,
  description: string = ""
): Promise<void> {
  const resp = await apiFetch("/api/skills", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, description }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => null);
    throw new Error(body?.error || `Failed to create skill: ${resp.status}`);
  }
}

export interface SkillReference {
  name: string;
}

export interface SkillReferences {
  workers: SkillReference[];
  stations: SkillReference[];
  crossTraining: SkillReference[];
  impliedBy: SkillReference[];
  implies: SkillReference[];
}

export async function deleteSkill(
  name: string
): Promise<{ ok: true } | { ok: false; references: SkillReferences }> {
  const resp = await apiFetch(`/api/skills/${encodeURIComponent(name)}`, { method: "DELETE" });
  if (resp.ok) return { ok: true };
  if (resp.status === 409) {
    const references: SkillReferences = await resp.json();
    return { ok: false, references };
  }
  throw new Error(`Failed to delete skill: ${resp.status}`);
}

export async function forceDeleteSkill(name: string): Promise<void> {
  const resp = await apiFetch(`/api/skills/${encodeURIComponent(name)}/force`, { method: "DELETE" });
  if (!resp.ok) throw new Error(`Failed to force-delete skill: ${resp.status}`);
}

export async function renameSkill(name: string, newName: string): Promise<void> {
  const resp = await apiFetch(`/api/skills/${encodeURIComponent(name)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: newName }),
  });
  if (!resp.ok) throw new Error(`Failed to rename skill: ${resp.status}`);
}

export async function addImplication(
  skillName: string,
  impliesSkillName: string
): Promise<void> {
  const resp = await apiFetch(`/api/skills/${encodeURIComponent(skillName)}/implications`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ impliesSkillName }),
  });
  if (!resp.ok) throw new Error(`Failed to add implication: ${resp.status}`);
}

export async function removeImplication(
  skillName: string,
  impliedName: string
): Promise<void> {
  const resp = await apiFetch(
    `/api/skills/${encodeURIComponent(skillName)}/implications/${encodeURIComponent(impliedName)}`,
    { method: "DELETE" }
  );
  if (!resp.ok) throw new Error(`Failed to remove implication: ${resp.status}`);
}
