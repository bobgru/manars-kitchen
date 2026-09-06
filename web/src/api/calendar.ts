import { apiFetch } from "./client";
import { fetchStations } from "./stations";
import { fetchWorkers } from "./workers";

/** A one-hour slot: `date` is YYYY-MM-DD, `start` is HH:MM, `duration` is seconds. */
export interface Slot {
  date: string;
  start: string;
  duration: number;
}

/** Worker and station arrive as numeric ids, not names -- see `fetchNameMaps`. */
export interface Assignment {
  worker: number;
  station: number;
  slot: Slot;
}

export interface CalendarCommit {
  id: number;
  committedAt: string;
  dateFrom: string;
  dateTo: string;
  note: string;
  /**
   * The draft this commit came from. Null for a commit that did not come from
   * one, and for commits written before the column existed. The draft itself is
   * deleted by the commit, so this is a label, not a fetchable id.
   */
  draftId: number | null;
}

/**
 * Id-to-name lookups for rendering assignments.
 *
 * The calendar endpoints identify workers and stations by id; the two list
 * endpoints report those same ids alongside the names.
 */
export interface NameMaps {
  workers: Map<number, string>;
  stations: Map<number, string>;
}

interface FreezeStatusResp {
  freezeLine: string;
}

export async function fetchCalendar(from: string, to: string): Promise<Assignment[]> {
  const resp = await apiFetch(
    `/api/calendar?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`
  );
  if (!resp.ok) throw new Error(`Failed to fetch calendar: ${resp.status}`);
  return resp.json();
}

export async function fetchCalendarHistory(): Promise<CalendarCommit[]> {
  const resp = await apiFetch("/api/calendar/history");
  if (!resp.ok) throw new Error(`Failed to fetch calendar history: ${resp.status}`);
  return resp.json();
}

export async function fetchCalendarCommit(id: number): Promise<Assignment[]> {
  const resp = await apiFetch(`/api/calendar/history/${encodeURIComponent(String(id))}`);
  if (!resp.ok) throw new Error(`Failed to fetch calendar commit: ${resp.status}`);
  return resp.json();
}

/** The freeze line as YYYY-MM-DD. Dates at or before it are frozen. */
export async function fetchFreezeLine(): Promise<string> {
  const resp = await apiFetch("/api/calendar/freeze-status");
  if (!resp.ok) throw new Error(`Failed to fetch freeze status: ${resp.status}`);
  const body: FreezeStatusResp = await resp.json();
  return body.freezeLine;
}

export async function fetchNameMaps(): Promise<NameMaps> {
  // "all", not "active": a past assignment can name a worker who has since
  // been deactivated, and it still has to render with a name.
  const [stations, workers] = await Promise.all([fetchStations(), fetchWorkers("all")]);
  return {
    workers: new Map(workers.map((w) => [w.id, w.name])),
    stations: new Map(stations.map((s) => [s.id, s.name])),
  };
}
