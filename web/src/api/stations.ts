import { apiFetch } from "./client";

export interface StationInfo {
  /** Storage id, matching the numeric `station` field of an Assignment. Not an address. */
  id: number;
  name: string;
  minStaff: number;
  maxStaff: number;
  /**
   * Free-text grouping label such as "hot line", or null. Stations sharing a
   * zone sit together in the problem view's station panel; the rest group
   * under "Unassigned". Not a coordinate — the floor plan is deferred (ADR 0004).
   */
  zone: string | null;
}

export async function fetchStations(): Promise<StationInfo[]> {
  const resp = await apiFetch("/api/stations");
  if (!resp.ok) throw new Error(`Failed to fetch stations: ${resp.status}`);
  return resp.json();
}

export async function createStation(
  name: string,
  minStaff: number = 1,
  maxStaff: number = 1
): Promise<void> {
  const resp = await apiFetch("/api/stations", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, minStaff, maxStaff }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => null);
    throw new Error(body?.error || `Failed to create station: ${resp.status}`);
  }
}

export interface StationReference {
  name: string;
}

export interface StationReferences {
  workerPrefs: StationReference[];
  requiredSkills: StationReference[];
}

export async function deleteStation(
  name: string
): Promise<{ ok: true } | { ok: false; references: StationReferences }> {
  const resp = await apiFetch(`/api/stations/${encodeURIComponent(name)}`, { method: "DELETE" });
  if (resp.ok) return { ok: true };
  if (resp.status === 409) {
    const references: StationReferences = await resp.json();
    return { ok: false, references };
  }
  throw new Error(`Failed to delete station: ${resp.status}`);
}

export async function forceDeleteStation(name: string): Promise<void> {
  const resp = await apiFetch(`/api/stations/${encodeURIComponent(name)}/force`, { method: "DELETE" });
  if (!resp.ok) throw new Error(`Failed to force-delete station: ${resp.status}`);
}

/**
 * Set or clear a station's zone. Blank and null both clear it; the server trims.
 */
export async function setStationZone(name: string, zone: string | null): Promise<void> {
  const resp = await apiFetch(`/api/stations/${encodeURIComponent(name)}/zone`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ zone }),
  });
  if (!resp.ok) throw new Error(`Failed to set station zone: ${resp.status}`);
}

export async function renameStation(name: string, newName: string): Promise<void> {
  const resp = await apiFetch(`/api/stations/${encodeURIComponent(name)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: newName }),
  });
  if (!resp.ok) throw new Error(`Failed to rename station: ${resp.status}`);
}
