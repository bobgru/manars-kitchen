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
  type Column,
  type GridLayout,
} from "../lib/grid";

interface Props {
  /** Which coordinates go on the axes. A named preset; see `GridLayout`. */
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

/** One assignment with everything the grid says about it already decided. */
interface Chip {
  a: Assignment;
  /** Undefined when there is no baseline to compare with. */
  state?: ChipState;
  /** The violated constraint, for a draft's own assignments only. */
  mark?: string;
}

/**
 * Consecutive hours of one chip's kind on one day, for the layouts whose rows
 * are not hours. A run breaks wherever anything about it changes -- the other
 * coordinate, the diff state, the mark -- so one chip never has to say two
 * things.
 */
interface Run {
  key: string;
  /** The first assignment; its worker and station stand for the run's. */
  a: Assignment;
  startHour: number;
  /** Exclusive. */
  endHour: number;
  state?: ChipState;
  mark?: string;
}

/**
 * A schedule rendered as a grid, shared by the calendar and by a draft.
 *
 * The range guard lives here rather than in either caller because this is the
 * component that cannot draw an oversized range -- a draft's dates are whatever
 * was typed at `draft create`.
 *
 * Empty-cell meaning is the layout's. In hours x days a cell is closed, unstaffed
 * or staffed. In workers x days an empty cell is a worker not on that day, and in
 * stations x days it is a station nobody is at that day; "closed" is not a thing
 * a worker-row can be. That is why the layouts are named presets (ADR 0005).
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

  // Decide everything about every chip once; the layouts only arrange them.
  // The chips are the draft's assignments plus, with a baseline, the
  // calendar's that the draft lacks.
  const chips = useMemo<Chip[]>(() => {
    const out: Chip[] = assignments.map((a) => ({
      a,
      state: diff ? (diff.added.has(assignmentKey(a)) ? "added" : "unchanged") : undefined,
      mark: markFor?.(a),
    }));
    // A dropped chip is the calendar's, not the draft's, so no draft violation
    // can be about it.
    for (const a of diff?.dropped ?? []) out.push({ a, state: "dropped" });
    return out;
  }, [assignments, diff, markFor]);

  // Index once per fetch: a month grid asks ~360 questions of this map.
  const byCell = useMemo(() => {
    const index = new Map<string, Chip[]>();
    for (const chip of chips) {
      const key = cellKey(chip.a.slot.date, slotHour(chip.a));
      const bucket = index.get(key);
      if (bucket) bucket.push(chip);
      else index.set(key, [chip]);
    }
    return index;
  }, [chips]);

  const hours = useMemo(() => {
    const set = new Set<number>();
    for (const c of columns) for (const h of c.open) set.add(h);
    // Station-specific hours can fall outside the defaults; never hide a slot.
    for (const chip of chips) set.add(slotHour(chip.a));
    return Array.from(set).sort((x, y) => x - y);
  }, [columns, chips]);

  const problem = rangeProblem(from, to);
  if (problem) return <p className="msg-error">{problem}</p>;

  function workerName(id: number): string {
    return names.workers.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number): string {
    return names.stations.get(id) ?? `station ${id}`;
  }

  const anyMarked = chips.some((c) => c.mark);

  /** The glyphs carry the meaning, not the colour: "!" violation, "+" added, "−" dropped. */
  function renderChip(key: string, state: ChipState | undefined, mark: string | undefined, body: string, detail: string) {
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
      <span className={classes.join(" ")} key={key} title={title}>
        {mark ? "! " : ""}
        {state === "added" ? "+ " : state === "dropped" ? "− " : ""}
        {body} <span className="calendar-chip-station">{detail}</span>
      </span>
    );
  }

  function columnHeader(c: Column) {
    return (
      <th
        key={c.day}
        className={
          [c.weekend ? "calendar-col-weekend" : "", c.frozen ? "calendar-col-frozen" : ""]
            .filter(Boolean)
            .join(" ") || undefined
        }
        title={c.frozen ? `${c.day} (frozen)` : c.day}
      >
        {c.label}
        {c.frozen ? " ❄" : ""}
      </th>
    );
  }

  const legendCommon = (
    <>
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
    </>
  );

  if (layout === "hours-days") {
    return (
      <>
        <div className="calendar-scroll">
          <table className="calendar-grid" data-layout={layout}>
            <thead>
              <tr>
                <th className="calendar-hour">Hour</th>
                {columns.map(columnHeader)}
              </tr>
            </thead>
            <tbody>
              {hours.map((h) => (
                <tr key={h}>
                  <td className="calendar-hour">{pad2(h)}:00</td>
                  {columns.map((c) => {
                    const cell = byCell.get(cellKey(c.day, h));
                    const closed = !c.open.has(h);
                    const classes = ["calendar-cell"];
                    if (c.weekend) classes.push("calendar-col-weekend");
                    if (closed) classes.push("calendar-cell-closed");
                    else if (!cell) classes.push("calendar-cell-empty");
                    return (
                      <td
                        key={c.day}
                        className={classes.join(" ")}
                        title={closed && !cell ? "Closed" : undefined}
                      >
                        {cell?.map(({ a, state, mark }) =>
                          renderChip(
                            `${state ?? ""}|${assignmentKey(a)}`,
                            state,
                            mark,
                            workerName(a.worker),
                            stationName(a.station)
                          )
                        )}
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
          {legendCommon}
        </div>
      </>
    );
  }

  // The two row-per-entity layouts differ only in which coordinate is the row.
  const byWorker = layout === "workers-days";
  const rowOf = (a: Assignment) => (byWorker ? a.worker : a.station);
  const otherOf = (a: Assignment) => (byWorker ? a.station : a.worker);
  const rowName = byWorker ? workerName : stationName;
  const otherName = byWorker ? stationName : workerName;

  const rows = Array.from(new Set(chips.map((c) => rowOf(c.a)))).sort((x, y) =>
    rowName(x).localeCompare(rowName(y))
  );

  // Runs per (row, day): sort each group's chips by hour and merge neighbours.
  const runs = new Map<string, Run[]>();
  const groups = new Map<string, Chip[]>();
  for (const chip of chips) {
    const k = `${rowOf(chip.a)}|${chip.a.slot.date}|${otherOf(chip.a)}|${chip.state ?? ""}|${chip.mark ?? ""}`;
    const g = groups.get(k);
    if (g) g.push(chip);
    else groups.set(k, [chip]);
  }
  for (const g of groups.values()) {
    g.sort((x, y) => slotHour(x.a) - slotHour(y.a));
    const cellK = `${rowOf(g[0].a)}|${g[0].a.slot.date}`;
    const list = runs.get(cellK) ?? [];
    let run: Run | null = null;
    for (const chip of g) {
      const h = slotHour(chip.a);
      if (run && h === run.endHour) {
        run.endHour = h + 1;
      } else {
        run = {
          key: `${chip.state ?? ""}|${assignmentKey(chip.a)}`,
          a: chip.a,
          startHour: h,
          endHour: h + 1,
          state: chip.state,
          mark: chip.mark,
        };
        list.push(run);
      }
    }
    runs.set(cellK, list);
  }
  for (const list of runs.values()) list.sort((x, y) => x.startHour - y.startHour);

  return (
    <>
      <div className="calendar-scroll">
        <table className="calendar-grid" data-layout={layout}>
          <thead>
            <tr>
              <th className="calendar-hour">{byWorker ? "Worker" : "Station"}</th>
              {columns.map(columnHeader)}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td className="calendar-hour">—</td>
                {columns.map((c) => (
                  <td key={c.day} className="calendar-cell calendar-cell-empty" />
                ))}
              </tr>
            )}
            {rows.map((r) => (
              <tr key={r}>
                <td className="calendar-hour calendar-row-name">{rowName(r)}</td>
                {columns.map((c) => {
                  const cell = runs.get(`${r}|${c.day}`);
                  const classes = ["calendar-cell"];
                  if (c.weekend) classes.push("calendar-col-weekend");
                  if (!cell) classes.push("calendar-cell-empty");
                  return (
                    <td key={c.day} className={classes.join(" ")}>
                      {cell?.map((run) =>
                        renderChip(
                          run.key,
                          run.state,
                          run.mark,
                          `${pad2(run.startHour)}–${pad2(run.endHour)}`,
                          otherName(otherOf(run.a))
                        )
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="calendar-legend">
        <span>
          {byWorker
            ? "A chip is one worker's run of consecutive hours at a station"
            : "A chip is one worker's run of consecutive hours at this station"}
        </span>
        <span>
          {byWorker ? "Empty: not scheduled that day" : "Empty: nobody at this station that day"}
        </span>
        {legendCommon}
      </div>
    </>
  );
}
