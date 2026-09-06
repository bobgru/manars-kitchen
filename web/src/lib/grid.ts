/**
 * The pure parts of the schedule grid: day arithmetic, opening hours, the range
 * guard, and cell indexing.
 *
 * These live apart from `components/ScheduleGrid.tsx` because
 * `react-refresh/only-export-components` forbids a file that exports both a
 * component and other values -- the same rule that split the SSE provider out of
 * `hooks/useSSE.tsx`.
 */
import type { Assignment } from "../api/calendar";

/**
 * One column per day, so a very wide range is unreadable as well as slow.
 * `ScheduleGrid` refuses anything longer rather than trusting callers: a draft's
 * date range is whatever was typed at `draft create`, unbounded.
 */
export const MAX_DAYS = 92;

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Which two coordinates of an assignment the grid puts on its axes.
 *
 * A named preset rather than a free `(rowAxis, colAxis)` pair, because
 * empty-cell meaning is axis-dependent and is most of what the grid knows: in
 * hours x days a cell is closed, unstaffed or staffed, and in a worker-rowed
 * layout "closed" means nothing. See ADR 0005.
 */
export type GridLayout = "hours-days";

/** A day column: its open hours, plus whether it is a weekend or frozen. */
export interface Column {
  day: string;
  label: string;
  weekend: boolean;
  frozen: boolean;
  open: Set<number>;
}

export function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

export function formatDay(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** Parse YYYY-MM-DD as a local-midnight Date, or null if malformed. */
export function parseDay(s: string): Date | null {
  if (!DAY_RE.test(s)) return null;
  const [y, m, d] = s.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  const roundTrips =
    dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d;
  return roundTrips ? dt : null;
}

function hourRange(start: number, end: number): number[] {
  const out: number[] = [];
  for (let h = start; h <= end; h++) out.push(h);
  return out;
}

/**
 * Opening hours per weekday, mirroring Domain.Calendar.defaultHours
 * (Mon-Fri 6..17, Sat 8..19, Sun 8..11). Hours outside this set are
 * structurally closed rather than merely unstaffed.
 */
function openHours(d: Date): number[] {
  switch (d.getDay()) {
    case 0:
      return hourRange(8, 11);
    case 6:
      return hourRange(8, 19);
    default:
      return hourRange(6, 17);
  }
}

function isWeekend(d: Date): boolean {
  const w = d.getDay();
  return w === 0 || w === 6;
}

/** Non-empty message describing why a range cannot be rendered. */
export function rangeProblem(from: string, to: string): string {
  const f = parseDay(from);
  const t = parseDay(to);
  if (!f || !t) return "Pick a valid from and to date.";
  if (f > t) return "The from date must not be after the to date.";
  const days = Math.round((t.getTime() - f.getTime()) / 86400000) + 1;
  if (days > MAX_DAYS) return `Range covers ${days} days; pick ${MAX_DAYS} or fewer.`;
  return "";
}

export function buildColumns(from: string, to: string, freezeLine: string): Column[] {
  const f = parseDay(from);
  const t = parseDay(to);
  if (!f || !t || rangeProblem(from, to)) return [];
  const cols: Column[] = [];
  const cursor = new Date(f);
  while (cursor <= t) {
    const day = formatDay(cursor);
    cols.push({
      day,
      label: `${WEEKDAYS[cursor.getDay()]} ${day.slice(5)}`,
      weekend: isWeekend(cursor),
      frozen: freezeLine !== "" && day <= freezeLine,
      open: new Set(openHours(cursor)),
    });
    cursor.setDate(cursor.getDate() + 1);
  }
  return cols;
}

export function slotHour(a: Assignment): number {
  return Number(a.slot.start.slice(0, 2));
}

export function cellKey(day: string, hour: number): string {
  return `${day}|${hour}`;
}

/** A stable identity for one assignment, for React keys and mark lookups. */
export function assignmentKey(a: Assignment): string {
  return `${a.slot.date}|${a.slot.start}|${a.worker}|${a.station}`;
}
