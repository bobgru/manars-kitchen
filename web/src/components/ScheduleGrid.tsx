import { useMemo } from "react";
import type { Assignment, NameMaps } from "../api/calendar";
import {
  buildColumns,
  cellKey,
  slotHour,
  assignmentKey,
  pad2,
  rangeProblem,
  type GridLayout,
} from "../lib/grid";

interface Props {
  /** Which coordinates go on the axes. Only "hours-days" exists so far. */
  layout: GridLayout;
  assignments: Assignment[];
  /** Inclusive range, YYYY-MM-DD. Wider than MAX_DAYS renders a refusal. */
  from: string;
  to: string;
  names: NameMaps;
  /** Dates at or before this are marked frozen. Empty string means none are. */
  freezeLine: string;
  /**
   * Flags one chip and supplies the prose for its tooltip. Used for draft
   * violations; the calendar has nothing to flag and omits it.
   */
  markFor?: (a: Assignment) => string | undefined;
}

/**
 * A schedule rendered as a grid, shared by the calendar and by a draft.
 *
 * The range guard lives here rather than in either caller because this is the
 * component that cannot draw an oversized range -- a draft's dates are whatever
 * was typed at `draft create`.
 */
export default function ScheduleGrid({
  layout,
  assignments,
  from,
  to,
  names,
  freezeLine,
  markFor,
}: Props) {
  const columns = useMemo(
    () => buildColumns(from, to, freezeLine),
    [from, to, freezeLine]
  );

  // Index once per fetch: a month grid asks ~360 questions of this map.
  const byCell = useMemo(() => {
    const index = new Map<string, Assignment[]>();
    for (const a of assignments) {
      const key = cellKey(a.slot.date, slotHour(a));
      const bucket = index.get(key);
      if (bucket) bucket.push(a);
      else index.set(key, [a]);
    }
    return index;
  }, [assignments]);

  const hours = useMemo(() => {
    const set = new Set<number>();
    for (const c of columns) for (const h of c.open) set.add(h);
    // Station-specific hours can fall outside the defaults; never hide a slot.
    for (const a of assignments) set.add(slotHour(a));
    return Array.from(set).sort((x, y) => x - y);
  }, [columns, assignments]);

  const problem = rangeProblem(from, to);
  if (problem) return <p className="msg-error">{problem}</p>;

  // One layout so far; the pivot control arrives with the second.
  if (layout !== "hours-days") return null;

  function workerName(id: number): string {
    return names.workers.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number): string {
    return names.stations.get(id) ?? `station ${id}`;
  }

  const anyMarked = markFor !== undefined && assignments.some((a) => markFor(a));

  return (
    <>
      <div className="calendar-scroll">
        <table className="calendar-grid">
          <thead>
            <tr>
              <th className="calendar-hour">Hour</th>
              {columns.map((c) => (
                <th
                  key={c.day}
                  className={
                    [
                      c.weekend ? "calendar-col-weekend" : "",
                      c.frozen ? "calendar-col-frozen" : "",
                    ]
                      .filter(Boolean)
                      .join(" ") || undefined
                  }
                  title={c.frozen ? `${c.day} (frozen)` : c.day}
                >
                  {c.label}
                  {c.frozen ? " ❄" : ""}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {hours.map((h) => (
              <tr key={h}>
                <td className="calendar-hour">{pad2(h)}:00</td>
                {columns.map((c) => {
                  const chips = byCell.get(cellKey(c.day, h));
                  const closed = !c.open.has(h);
                  const classes = ["calendar-cell"];
                  if (c.weekend) classes.push("calendar-col-weekend");
                  if (closed) classes.push("calendar-cell-closed");
                  else if (!chips) classes.push("calendar-cell-empty");
                  return (
                    <td
                      key={c.day}
                      className={classes.join(" ")}
                      title={closed && !chips ? "Closed" : undefined}
                    >
                      {chips?.map((a) => {
                        const mark = markFor?.(a);
                        return (
                          <span
                            className={
                              mark
                                ? "calendar-chip calendar-chip-flagged"
                                : "calendar-chip"
                            }
                            key={assignmentKey(a)}
                            title={mark}
                          >
                            {/* The "!" carries the meaning, not the colour. */}
                            {mark ? "! " : ""}
                            {workerName(a.worker)}{" "}
                            <span className="calendar-chip-station">
                              {stationName(a.station)}
                            </span>
                          </span>
                        );
                      })}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="calendar-legend">
        <span>Unstaffed: open but nobody assigned</span>
        <span>Darker: outside that weekday's opening hours</span>
        <span>Tinted column: weekend</span>
        <span>
          &#10052; frozen
          {freezeLine ? ` (at or before ${freezeLine})` : ""}
        </span>
        {anyMarked && <span>! violates a hard rule; listed below</span>}
      </div>
    </>
  );
}
