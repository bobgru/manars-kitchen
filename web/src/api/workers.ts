import { apiFetch } from "./client";

export type WorkerStatus = "active" | "inactive" | "none";
export type StatusFilter = "active" | "inactive" | "all";

export interface WorkerSummary {
  name: string;
  role: string;
  status: WorkerStatus;
  isTemp: boolean;
  weekendOnly: boolean;
  seniority: number;
}

export interface WorkerProfile {
  name: string;
  userId: number;
  workerId: number;
  role: string;
  status: WorkerStatus;
  deactivatedAt?: string | null;
  overtimeModel: string;
  payPeriodTracking: string;
  isTemp: boolean;
  maxPeriodHours?: number | null;
  overtimeOptIn: boolean;
  weekendOnly: boolean;
  prefersVariety: boolean;
  seniority: number;
  skills: string[];
  stationPrefs: string[];
  shiftPrefs: string[];
  crossTraining: string[];
  avoidPairing: string[];
  preferPairing: string[];
}

export interface DeactivationImpact {
  pinsRemoved: number;
  draftsRemoved: number;
  calendarRemoved: number;
}

export interface WorkerReferences {
  configuration: string[];
  schedule: string[];
}

export interface CreateUserReq {
  username: string;
  password: string;
  role: string;
  noWorker?: boolean;
}

export async function fetchWorkers(status: StatusFilter = "active"): Promise<WorkerSummary[]> {
  const resp = await apiFetch(`/api/workers?status=${encodeURIComponent(status)}`);
  if (!resp.ok) throw new Error(`Failed to fetch workers: ${resp.status}`);
  return resp.json();
}

export async function fetchWorkerProfile(name: string): Promise<WorkerProfile> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}`);
  if (!resp.ok) throw new Error(`Failed to fetch worker: ${resp.status}`);
  return resp.json();
}

export async function deactivateWorker(
  name: string
): Promise<{ ok: true } | { ok: false; impact: DeactivationImpact }> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}/deactivate`, {
    method: "PUT",
  });
  if (resp.status === 204) return { ok: true };
  if (resp.status === 409) {
    const impact: DeactivationImpact = await resp.json();
    return { ok: false, impact };
  }
  throw new Error(`Failed to deactivate worker: ${resp.status}`);
}

export async function forceDeactivateWorker(name: string): Promise<DeactivationImpact> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}/deactivate/force`, {
    method: "PUT",
  });
  if (!resp.ok) throw new Error(`Failed to force-deactivate worker: ${resp.status}`);
  return resp.json();
}

export async function activateWorker(name: string): Promise<void> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}/activate`, {
    method: "PUT",
  });
  if (!resp.ok) throw new Error(`Failed to activate worker: ${resp.status}`);
}

export async function deleteWorker(
  name: string
): Promise<{ ok: true } | { ok: false; references: WorkerReferences }> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}`, { method: "DELETE" });
  if (resp.status === 204) return { ok: true };
  if (resp.status === 409) {
    const references: WorkerReferences = await resp.json();
    return { ok: false, references };
  }
  throw new Error(`Failed to delete worker: ${resp.status}`);
}

export async function forceDeleteWorker(name: string): Promise<void> {
  const resp = await apiFetch(`/api/workers/${encodeURIComponent(name)}/force`, {
    method: "DELETE",
  });
  if (!resp.ok) throw new Error(`Failed to force-delete worker: ${resp.status}`);
}

export async function renameWorker(name: string, newName: string): Promise<void> {
  // Server's rename endpoint is keyed by user id. Look up the worker profile
  // to resolve the id, then issue the rename.
  const profile = await fetchWorkerProfile(name);
  const resp = await apiFetch(`/api/users/${profile.userId}/rename`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: newName }),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => null);
    throw new Error(body?.error || `Failed to rename worker: ${resp.status}`);
  }
}

export async function createUser(req: CreateUserReq): Promise<void> {
  const resp = await apiFetch("/api/users", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => null);
    throw new Error(body?.error || `Failed to create user: ${resp.status}`);
  }
}
