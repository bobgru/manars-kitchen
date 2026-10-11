import { useMemo } from "react";
import type { Assignment, NameMaps } from "../api/calendar";
import {
  buildColumns,
  cellKey,
  slotHour,
  assignmentKey,
  pad2,
  rangeProblem,
  diffAgainstCalendar,
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
  /**
   * The calendar's assignments over the same range. When given, every chip is
   * classified against it -- added by this commit, or already there -- and the
   * calendar assignments the draft lacks are drawn too, struck through, because
   * committing drops them. A draft wants this; the calendar, compared with
   * itself, does not.
   */
  baseline?: Assignment[];
}

type ChipState = "added" | "unchanged" | "dropped";

interface Chip {
  a: Assignment;
  /** Undefined when there is no baseline to compare with. */
  state?: ChipState;
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
  baseline,
}: Props) {
  const columns = useMemo(
    () => buildColumns(from, to, freezeLine),
    [from, to, freezeLine]
  );

  const diff = useMemo(
    () => (baseline ? diffAgainstCalendar(assignments, baseline) : null),
    [assignments, baseline]
  );

  // Index once per fetch: a month grid asks ~360 questions of this map. The
  // chips are the draft's assignments plus, with a baseline, the calendar's
  // that the draft lacks.
  const byCell = useMemo(() => {
    const index = new Map<string, Chip[]>();
    const put = (chip: Chip) => {
      const key = cellKey(chip.a.slot.date, slotHour(chip.a));
      const bucket = index.get(key);
      if (bucket) bucket.push(chip);
      else index.set(key, [chip]);
    };
    for (const a of assignments) {
      put({
        a,
        state: diff ? (diff.added.has(assignmentKey(a)) ? "added" : "unchanged") : undefined,
      });
    }
    for (const a of diff?.dropped ?? []) put({ a, state: "dropped" });
    return index;
  }, [assignments, diff]);

  const hours = useMemo(() => {
    const set = new Set<number>();
    for (const c of columns) for (const h of c.open) set.add(h);
    // Station-specific hours can fall outside the defaults; never hide a slot.
    for (const a of assignments) set.add(slotHour(a));
    for (const a of diff?.dropped ?? []) set.add(slotHour(a));
    return Array.from(set).sort((x, y) => x - y);
  }, [columns, assignments, diff]);

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
                      {chips?.map(({ a, state }) => {
                        // A dropped chip is the calendar's, not the draft's, so
                        // no draft violation can be about it.
                        const mark = state === "dropped" ? undefined : markFor?.(a);
                        const classes = ["calendar-chip"];
                        if (mark) classes.push("calendar-chip-flagged");
                        if (state === "added") classes.push("calendar-chip-added");
                        if (state === "dropped") classes.push("calendar-chip-dropped");
                        const title =
                          state === "dropped"
                            ? "On the calendar now; committing this draft drops it"
                            : state === "added"
                              ? mark
                                ? `${mark} — not on the calendar; committing adds it`
                                : "Not on the calendar; committing adds it"
                              : mark;
                        return (
                          <span
                            className={classes.join(" ")}
                            key={`${state ?? ""}|${assignmentKey(a)}`}
                            title={title}
                          >
                            {/* The glyphs carry the meaning, not the colour: "!"
                                for a violation, "+" for added, "−" for dropped. */}
                            {mark ? "! " : ""}
                            {state === "added" ? "+ " : state === "dropped" ? "− " : ""}
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
        {diff && (
          <>
            <span>+ not on the calendar; committing adds it</span>
            <span>
              <s>− struck through</s>: on the calendar now; committing drops it
            </span>
          </>
        )}
      </div>
    </>
  );
}
