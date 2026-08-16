import { apiFetch } from "./client";

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
}

/**
 * Id-to-name lookups for rendering assignments.
 *
 * The calendar endpoints identify workers and stations by id, but neither
 * `/api/workers` nor `/api/stations` includes ids in its payload, so they
 * cannot resolve them. `/api/export` is the only read endpoint that exposes
 * both id-to-name mappings, so it is used here as the name source.
 */
export interface NameMaps {
  workers: Map<number, string>;
  stations: Map<number, string>;
}

interface FreezeStatusResp {
  freezeLine: string;
}

interface ExportResp {
  workers?: { id: number; username: string }[];
  stations?: { id: number; name: string }[];
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
  const resp = await apiFetch("/api/export");
  if (!resp.ok) throw new Error(`Failed to fetch names: ${resp.status}`);
  const body: ExportResp = await resp.json();
  return {
    workers: new Map((body.workers ?? []).map((w) => [w.id, w.username])),
    stations: new Map((body.stations ?? []).map((s) => [s.id, s.name])),
  };
}
