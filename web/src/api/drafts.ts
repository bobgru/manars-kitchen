import { apiFetch } from "./client";
import type { Assignment, CalendarCommit } from "./calendar";

/** Draft metadata as `/api/drafts` reports it. Dates are YYYY-MM-DD. */
export interface DraftInfo {
  id: number;
  dateFrom: string;
  dateTo: string;
  createdAt: string;
  lastValidatedAt: string;
}

/** A hard-constraint violation. Both strings are already user-facing prose. */
export interface DraftViolation {
  assignment: Assignment;
  constraint: string;
  reason: string;
}

/**
 * What a draft holds and what is wrong with it.
 *
 * `violations` is a report, not a diff: the assignments it names are still in
 * `assignments`. `replacedUnder` is the calendar commits that overwrote part of
 * this draft's own date range since it was last validated — the draft was seeded
 * from a calendar that has since moved.
 */
export interface DraftAssignments {
  assignments: Assignment[];
  violations: DraftViolation[];
  replacedUnder: CalendarCommit[];
}

/**
 * The 409 body when a draft's range covers frozen dates.
 *
 * Terminal over HTTP: there is no force and no unfreeze on this API, so the only
 * ways forward are a later range or `calendar unfreeze` in the CLI.
 */
export interface FrozenDates {
  error: string;
  freezeLine: string;
  frozenFrom: string;
  frozenTo: string;
}

/** The 409 body when other drafts cover the dates a commit would overwrite. */
export interface OverlappingDrafts {
  error: string;
  drafts: DraftInfo[];
}

/** What `generate` reports back. Only the counts are used here. */
export interface GenerateResult {
  schedule: Assignment[];
  unfilled: unknown[];
}

/**
 * How a calendar commit is named in prose, for the "calendar replaced by ..."
 * warning. Lives here rather than in a page because both the drafts list and a
 * draft's own page show it and the wording must not drift.
 *
 * A commit's `draftId` names a draft the commit itself deleted, so it is a label
 * the admin recognises rather than something fetchable.
 */
export function describeCommit(c: CalendarCommit): string {
  if (c.draftId !== null) return `draft #${c.draftId}`;
  return c.note ? `commit #${c.id} (${c.note})` : `commit #${c.id}`;
}

export async function fetchDrafts(): Promise<DraftInfo[]> {
  const resp = await apiFetch("/api/drafts");
  if (!resp.ok) throw new Error(`Failed to fetch drafts: ${resp.status}`);
  return resp.json();
}

/**
 * One draft's metadata. Needed alongside the assignments read, which does not
 * report the date range the grid has to be drawn over.
 */
export async function fetchDraft(id: number): Promise<DraftInfo> {
  const resp = await apiFetch(`/api/drafts/${id}`);
  if (!resp.ok) throw new Error(`Failed to fetch draft ${id}: ${resp.status}`);
  return resp.json();
}

/** A pure read: reports violations without pruning them. */
export async function fetchDraftAssignments(id: number): Promise<DraftAssignments> {
  const resp = await apiFetch(`/api/drafts/${id}/assignments`);
  if (!resp.ok) throw new Error(`Failed to fetch draft ${id}: ${resp.status}`);
  return resp.json();
}

export async function createDraft(
  dateFrom: string,
  dateTo: string
): Promise<{ ok: true; id: number } | { ok: false; frozen: FrozenDates }> {
  const resp = await apiFetch("/api/drafts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ dateFrom, dateTo }),
  });
  if (resp.ok) {
    const body: { id: number } = await resp.json();
    return { ok: true, id: body.id };
  }
  if (resp.status === 409) {
    const frozen: FrozenDates = await resp.json();
    return { ok: false, frozen };
  }
  throw new Error(`Failed to create draft: ${resp.status}`);
}

/**
 * Run the scheduler inside a draft. `workerIds` is deliberately omitted so the
 * server defaults to the active workers — sending `[]` would mean "schedule
 * nobody" and be honoured.
 */
export async function generateDraft(id: number): Promise<GenerateResult> {
  const resp = await apiFetch(`/api/drafts/${id}/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  if (!resp.ok) throw new Error(`Failed to generate draft: ${resp.status}`);
  return resp.json();
}

export async function commitDraft(
  id: number,
  note: string
): Promise<{ ok: true } | { ok: false; overlapping: OverlappingDrafts }> {
  const resp = await apiFetch(`/api/drafts/${id}/commit`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ note }),
  });
  if (resp.status === 204) return { ok: true };
  if (resp.status === 409) {
    const overlapping: OverlappingDrafts = await resp.json();
    return { ok: false, overlapping };
  }
  throw new Error(`Failed to commit draft: ${resp.status}`);
}

/**
 * Commit past the overlapping-drafts refusal. The overlapping siblings are left
 * in place; what is lost is their claim on the calendar for those dates, which
 * the history snapshot can restore.
 */
export async function forceCommitDraft(id: number, note: string): Promise<void> {
  const resp = await apiFetch(`/api/drafts/${id}/commit/force`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ note }),
  });
  if (!resp.ok) throw new Error(`Failed to force-commit draft: ${resp.status}`);
}

export async function discardDraft(id: number): Promise<void> {
  const resp = await apiFetch(`/api/drafts/${id}`, { method: "DELETE" });
  if (!resp.ok) throw new Error(`Failed to discard draft: ${resp.status}`);
}
