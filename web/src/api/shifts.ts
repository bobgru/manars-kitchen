import { apiFetch } from "./client";

export interface ShiftInfo {
  name: string;
  start: number;
  end: number;
}

export async function fetchShifts(): Promise<ShiftInfo[]> {
  const resp = await apiFetch("/api/shifts");
  if (!resp.ok) throw new Error(`Failed to fetch shifts: ${resp.status}`);
  return resp.json();
}

export async function createShift(
  name: string,
  start: number,
  end: number
): Promise<void> {
  const resp = await apiFetch("/api/shifts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, start, end }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => null);
    throw new Error(body?.error || `Failed to create shift: ${resp.status}`);
  }
}

export async function deleteShift(name: string): Promise<void> {
  const resp = await apiFetch(`/api/shifts/${encodeURIComponent(name)}`, {
    method: "DELETE",
  });
  if (!resp.ok) throw new Error(`Failed to delete shift: ${resp.status}`);
}
