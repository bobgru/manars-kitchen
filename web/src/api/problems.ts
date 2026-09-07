import { apiFetch } from "./client";
import type { Assignment, Slot } from "./calendar";

/**
 * Which kind of problem this is. `kind` picks the wording; `severityRank` is what
 * a cell aggregates on, higher being more severe. Both come from the server so
 * that no client owns the ordering — see ADR 0006.
 *
 * `compromise` does not exist yet: it is piece 5 of item 2 in `docs/STATUS.md`.
 * It is in the union because the server will start sending it without a version
 * bump, and a client that switched exhaustively today would break silently then.
 */
export type ProblemKind = "violation" | "understaffed" | "compromise";

/**
 * What a problem is scoped to. Everything today is `slot`-scoped; `day` exists
 * because a worker over their pay-period hour limit is a fact about many stations
 * across many days.
 */
export interface ProblemScope {
  kind: "slot" | "day";
  slot?: Slot;
  day?: string;
}

/** A hard-rule violation, as the draft validator reports it. */
export interface ViolationDetail {
  assignment: Assignment;
  constraint: string;
  reason: string;
}

/**
 * One thing wanting an admin's attention.
 *
 * `worker` and `station` are nullable because not every problem has both:
 * understaffing is a station-and-slot fact with nobody in it, which is the
 * problem. These two plus the scope are the envelope the projections filter on.
 */
export interface Problem {
  kind: ProblemKind;
  severityRank: number;
  worker: number | null;
  station: number | null;
  scope: ProblemScope;
  earliestDay: string;
  /** Present when `kind` is "violation". */
  violation?: ViolationDetail;
  /** Both present when `kind` is "understaffed". */
  assigned?: number;
  required?: number;
}

/**
 * One selectable date range. Both ends inclusive.
 *
 * The label for a pay period is a date range rather than a word, because
 * `PayPeriodType` is configurable and "this week" would be a lie for a
 * monthly-paid restaurant.
 */
export interface Horizon {
  key: string;
  label: string;
  from: string;
  to: string;
}

/**
 * The three ranges the horizon control offers: today, the current pay period, the
 * next. Fetched rather than computed because `payPeriodBounds` lives on the
 * server and depends on configuration.
 */
export async function fetchHorizons(): Promise<Horizon[]> {
  const resp = await apiFetch("/api/horizons");
  if (!resp.ok) throw new Error(`Failed to fetch horizons: ${resp.status}`);
  return resp.json();
}

/**
 * Every problem in an inclusive date range. Both dates are required: a problem
 * set without a range is meaningless, and the server refuses to invent one.
 */
export async function fetchProblems(from: string, to: string): Promise<Problem[]> {
  const resp = await apiFetch(
    `/api/problems?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`
  );
  if (!resp.ok) throw new Error(`Failed to fetch problems: ${resp.status}`);
  return resp.json();
}

/** The day a problem sits on, whichever way it is scoped. */
export function problemDay(p: Problem): string {
  if (p.scope.kind === "slot" && p.scope.slot) return p.scope.slot.date;
  return p.scope.day ?? p.earliestDay;
}

/** The hour a slot-scoped problem sits in, or null for a day-scoped one. */
export function problemHour(p: Problem): number | null {
  if (p.scope.kind === "slot" && p.scope.slot) {
    return Number(p.scope.slot.start.slice(0, 2));
  }
  return null;
}

/**
 * The short word a cell shows for a kind, paired with a glyph rather than a
 * colour so the meaning survives when two colours look identical.
 */
export function kindGlyph(kind: ProblemKind): string {
  switch (kind) {
    case "violation":
      return "!";
    case "understaffed":
      return "▼"; // black down-pointing triangle: below minimum
    case "compromise":
      return "~";
  }
}

export function kindLabel(kind: ProblemKind): string {
  switch (kind) {
    case "violation":
      return "Violation";
    case "understaffed":
      return "Understaffed";
    case "compromise":
      return "Compromise";
  }
}
