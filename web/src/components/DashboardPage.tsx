import { useState, useEffect, useCallback, useMemo } from "react";
import type { JSX } from "react";
import {
  fetchHorizons,
  fetchProblems,
  problemDay,
  problemHour,
  kindGlyph,
  kindLabel,
  type Horizon,
  type Problem,
} from "../api/problems";
import { fetchFreezeLine } from "../api/calendar";
import { fetchWorkers, type WorkerSummary } from "../api/workers";
import { fetchStations, type StationInfo } from "../api/stations";
import { useEntityEvents } from "../hooks/useSSE";
import { buildColumns, cellKey, pad2, type Column } from "../lib/grid";

/** The most severe problem in a group. Severity ordering comes from the server. */
function mostSevere(problems: Problem[]): Problem {
  return problems.reduce((worst, p) =>
    p.severityRank > worst.severityRank ? p : worst
  );
}

/** The earliest day any of these problems affects, or null for none. */
function earliestDay(problems: Problem[]): string | null {
  if (problems.length === 0) return null;
  return problems.reduce(
    (min, p) => (p.earliestDay < min ? p.earliestDay : min),
    problems[0].earliestDay
  );
}

/**
 * Which of the three panels a cell belongs to. All three share the day columns;
 * they differ in what a row is, and so in what `row` means: an hour of the day,
 * a worker id, or a station id.
 */
type Panel = "hour" | "worker" | "station";

interface CellRef {
  panel: Panel;
  row: number;
  day: string;
}

/** Index key for a worker-row or station-row cell. */
function rowKey(id: number, day: string): string {
  return `${id}|${day}`;
}

/** A row of the worker panel. Inactive workers appear only when a problem names them. */
interface WorkerRow {
  id: number;
  name: string;
  active: boolean;
}

/** A zone's worth of station rows. `zone` is null for the "Unassigned" group. */
interface ZoneGroup {
  zone: string | null;
  stations: { id: number; name: string }[];
}

function byName<T extends { name: string }>(a: T, b: T): number {
  return a.name.localeCompare(b.name);
}

function sameCell(a: CellRef | null, b: CellRef): boolean {
  return a !== null && a.panel === b.panel && a.row === b.row && a.day === b.day;
}

function refKey(ref: CellRef): string {
  return `${ref.panel}|${ref.row}|${ref.day}`;
}

/**
 * The cells one problem occupies, at most one per panel: its hour in the hour
 * panel if it is slot-scoped, its worker's row and its station's row if it names
 * them. An unscheduled day occupies none, which is why it lives in the header.
 */
function cellsOf(p: Problem): CellRef[] {
  const day = problemDay(p);
  const out: CellRef[] = [];
  const hour = problemHour(p);
  if (hour !== null) out.push({ panel: "hour", row: hour, day });
  if (p.worker !== null) out.push({ panel: "worker", row: p.worker, day });
  if (p.station !== null) out.push({ panel: "station", row: p.station, day });
  return out;
}

/**
 * The problem view: what is wrong with the committed calendar, over a horizon.
 *
 * This is the main view, not a summary of entities — most days an admin is not
 * building a schedule but reacting to something that broke one. ADR 0004.
 *
 * One fetch covers all three horizons. Today sits inside the current pay period,
 * so the union of the three ranges is `[currentPeriodStart, nextPeriodEnd]`, and
 * each segment's mark plus the grid are date filters over one result set. That is
 * what stops the marks disagreeing with the view they select — see ADR 0006.
 *
 * Three panels project the same problem set: by hour, by worker, and by station
 * grouped by zone. They are three row groups of one table so that a date lines up
 * vertically across all of them and there is one horizontal scroll. Each cell is a
 * glyph plus a count, never colour alone, and the most severe kind in the cell
 * decides the glyph.
 */
export default function DashboardPage() {
  const [horizons, setHorizons] = useState<Horizon[]>([]);
  const [selectedKey, setSelectedKey] = useState("current-period");
  const [problems, setProblems] = useState<Problem[]>([]);
  const [workers, setWorkers] = useState<WorkerSummary[]>([]);
  const [stations, setStations] = useState<StationInfo[]>([]);
  const [freezeLine, setFreezeLine] = useState("");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedCell, setSelectedCell] = useState<CellRef | null>(null);
  // One problem picked out of the selected cell's list. Its worker row, station
  // row and hour cell are outlined across the panels and named in a caption, so
  // three outlines never have to be decoded on their own — ADR 0006.
  const [focus, setFocus] = useState<Problem | null>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      // The horizons decide the range to fetch, so they come first. Workers,
      // stations and the freeze line shape the rows and decorate the columns;
      // they fall back to empty rather than failing the view.
      //
      // "all" workers, not "active": a committed assignment can name a worker
      // who has since been deactivated, and their violations still need a row.
      const [hs, ws, sts, freeze] = await Promise.all([
        fetchHorizons(),
        fetchWorkers("all").catch(() => [] as WorkerSummary[]),
        fetchStations().catch(() => [] as StationInfo[]),
        fetchFreezeLine().catch(() => ""),
      ]);
      setHorizons(hs);
      setWorkers(ws);
      setStations(sts);
      setFreezeLine(freeze);
      if (hs.length === 0) {
        setProblems([]);
        return;
      }
      const unionFrom = hs.reduce((a, h) => (h.from < a ? h.from : a), hs[0].from);
      const unionTo = hs.reduce((a, h) => (h.to > a ? h.to : a), hs[0].to);
      setProblems(await fetchProblems(unionFrom, unionTo));
      // The focused problem is an object from the previous result set; the
      // selected cell survives a reload because it is a position, but a problem
      // may no longer exist.
      setFocus(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  // The problem set depends on far more than the calendar: approving an absence or
  // revoking a skill invalidates assignments without touching it. That is the
  // sick-call case ADR 0004 is built around, so every topic that can change the
  // answer is watched.
  useEntityEvents("calendar", load);
  useEntityEvents("draft", load);
  useEntityEvents("absence", load);
  useEntityEvents("worker", load);
  useEntityEvents("station", load);
  useEntityEvents("skill", load);

  const selected = horizons.find((h) => h.key === selectedKey) ?? horizons[0];

  const inRange = useCallback(
    (h: Horizon) => (p: Problem) => {
      const d = problemDay(p);
      return d >= h.from && d <= h.to;
    },
    []
  );

  const shown = useMemo(
    () => (selected ? problems.filter(inRange(selected)) : []),
    [problems, selected, inRange]
  );

  const columns = useMemo(
    () => (selected ? buildColumns(selected.from, selected.to, freezeLine) : []),
    [selected, freezeLine]
  );

  // A day nobody has staffed at all is one problem about the whole day, not a
  // grid of empty cells, so it belongs in the column header. The server has
  // already suppressed that day's per-slot understaffing — ADR 0007 — which is
  // why those columns come through empty. It names no worker and no station, so
  // no panel can put it on a row; every panel hatches the column instead.
  const unscheduledDays = useMemo(
    () =>
      new Set(
        shown.filter((p) => p.kind === "unscheduled").map((p) => problemDay(p))
      ),
    [shown]
  );

  // A day-scoped problem has no hour cell. If it names a worker or a station it
  // still gets a cell in that panel — a worker over their period hours is the
  // case that exists. One naming neither is reported in words rather than being
  // dropped silently.
  const dayScopedPlaced = useMemo(
    () =>
      shown.filter(
        (p) =>
          problemHour(p) === null &&
          p.kind !== "unscheduled" &&
          (p.worker !== null || p.station !== null)
      ),
    [shown]
  );
  const dayScopedUnplaced = useMemo(
    () =>
      shown.filter(
        (p) =>
          problemHour(p) === null &&
          p.kind !== "unscheduled" &&
          p.worker === null &&
          p.station === null
      ),
    [shown]
  );

  const byCell = useMemo(() => {
    const index = new Map<string, Problem[]>();
    for (const p of shown) {
      const hour = problemHour(p);
      if (hour === null) continue;
      const key = cellKey(problemDay(p), hour);
      const bucket = index.get(key);
      if (bucket) bucket.push(p);
      else index.set(key, [p]);
    }
    return index;
  }, [shown]);

  const byWorkerDay = useMemo(() => {
    const index = new Map<string, Problem[]>();
    for (const p of shown) {
      if (p.worker === null) continue;
      const key = rowKey(p.worker, problemDay(p));
      const bucket = index.get(key);
      if (bucket) bucket.push(p);
      else index.set(key, [p]);
    }
    return index;
  }, [shown]);

  const byStationDay = useMemo(() => {
    const index = new Map<string, Problem[]>();
    for (const p of shown) {
      if (p.station === null) continue;
      const key = rowKey(p.station, problemDay(p));
      const bucket = index.get(key);
      if (bucket) bucket.push(p);
      else index.set(key, [p]);
    }
    return index;
  }, [shown]);

  const hours = useMemo(() => {
    const set = new Set<number>();
    for (const c of columns) for (const h of c.open) set.add(h);
    // A problem can sit outside the default opening hours; never hide one.
    for (const p of shown) {
      const h = problemHour(p);
      if (h !== null) set.add(h);
    }
    return Array.from(set).sort((x, y) => x - y);
  }, [columns, shown]);

  // Every active worker has a row, so an empty row says "this person is fine".
  // Inactive workers appear only when a problem names them, and a worker id the
  // list does not know at all still gets a row rather than losing its problems.
  const workerRows = useMemo((): WorkerRow[] => {
    const named = new Set<number>();
    for (const p of shown) if (p.worker !== null) named.add(p.worker);
    const rows: WorkerRow[] = workers
      .filter((w) => w.status === "active" || named.has(w.id))
      .map((w) => ({ id: w.id, name: w.name, active: w.status === "active" }));
    const known = new Set(rows.map((r) => r.id));
    for (const id of named) {
      if (!known.has(id)) rows.push({ id, name: `worker ${id}`, active: false });
    }
    return rows.sort(byName);
  }, [workers, shown]);

  // Stations grouped by zone, zones alphabetical with "Unassigned" last, so a hot
  // area reads as a block. Every station has a row for the same reason every
  // active worker does.
  const zoneGroups = useMemo((): ZoneGroup[] => {
    const groups = new Map<string | null, ZoneGroup>();
    const add = (zone: string | null, id: number, name: string) => {
      const g = groups.get(zone);
      if (g) g.stations.push({ id, name });
      else groups.set(zone, { zone, stations: [{ id, name }] });
    };
    for (const s of stations) add(s.zone, s.id, s.name);
    const known = new Set(stations.map((s) => s.id));
    for (const p of shown) {
      if (p.station !== null && !known.has(p.station)) {
        known.add(p.station);
        add(null, p.station, `station ${p.station}`);
      }
    }
    const out = Array.from(groups.values());
    for (const g of out) g.stations.sort(byName);
    return out.sort((a, b) => {
      if (a.zone === null) return 1;
      if (b.zone === null) return -1;
      return a.zone.localeCompare(b.zone);
    });
  }, [stations, shown]);

  const focusedCells = useMemo(
    () => new Set(focus ? cellsOf(focus).map(refKey) : []),
    [focus]
  );

  const workerNames = useMemo(
    () => new Map(workers.map((w) => [w.id, w.name])),
    [workers]
  );
  const stationNames = useMemo(
    () => new Map(stations.map((s) => [s.id, s.name])),
    [stations]
  );

  function workerName(id: number | null): string {
    if (id === null) return "nobody";
    return workerNames.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number | null): string {
    if (id === null) return "no station";
    return stationNames.get(id) ?? `station ${id}`;
  }

  /** One problem as a sentence, for the detail pane. */
  function describe(p: Problem): string {
    if (p.kind === "violation" && p.violation) {
      return (
        `${workerName(p.worker)} at ${stationName(p.station)} — ` +
        `${p.violation.constraint}: ${p.violation.reason}`
      );
    }
    if (p.kind === "understaffed") {
      return (
        `${stationName(p.station)} — ${p.assigned ?? 0} of ${p.required ?? 0} ` +
        `staffed`
      );
    }
    if (p.kind === "unscheduled") {
      return `${problemDay(p)} — nobody is scheduled on this day at all`;
    }
    return `${kindLabel(p.kind)} — ${stationName(p.station)}`;
  }

  /** The problems behind a cell, whichever panel it is in. */
  function problemsAt(ref: CellRef): Problem[] {
    switch (ref.panel) {
      case "hour":
        return byCell.get(cellKey(ref.day, ref.row)) ?? [];
      case "worker":
        return byWorkerDay.get(rowKey(ref.row, ref.day)) ?? [];
      case "station":
        return byStationDay.get(rowKey(ref.row, ref.day)) ?? [];
    }
  }

  /** Where one problem sits, in words: "Ana · grill · 2026-10-08 10:00". */
  function whereIs(p: Problem): string {
    const parts: string[] = [];
    if (p.worker !== null) parts.push(workerName(p.worker));
    if (p.station !== null) parts.push(stationName(p.station));
    const hour = problemHour(p);
    parts.push(hour === null ? problemDay(p) : `${problemDay(p)} ${pad2(hour)}:00`);
    return parts.join(" · ");
  }

  /** The caption for a selected cell: which row, which day, in words. */
  function captionFor(ref: CellRef): string {
    switch (ref.panel) {
      case "hour":
        return `${ref.day} at ${pad2(ref.row)}:00`;
      case "worker":
        return `${workerName(ref.row)} on ${ref.day}`;
      case "station":
        return `${stationName(ref.row)} on ${ref.day}`;
    }
  }

  /**
   * One cell of any panel. `closed` only means something in the hour panel,
   * where an hour outside opening time is structurally different from an
   * unstaffed one; in a worker or station row an empty cell just means nothing
   * is wrong there, which is why ADR 0005 keeps empty-cell meaning per layout.
   */
  function renderCell(ref: CellRef, col: Column, closed: boolean): JSX.Element {
    const here = problemsAt(ref);
    const has = here.length > 0;
    const unscheduled = unscheduledDays.has(col.day);
    const classes = ["problem-cell"];
    if (col.weekend) classes.push("calendar-col-weekend");
    if (closed && !has) classes.push("calendar-cell-closed");
    if (unscheduled && !closed && !has) classes.push("problem-cell-unscheduled");
    if (sameCell(selectedCell, ref)) classes.push("problem-cell-selected");
    if (focusedCells.has(refKey(ref))) classes.push("problem-cell-focus");
    if (has) classes.push(`problem-cell-${mostSevere(here).kind}`);
    return (
      <td
        key={col.day}
        className={classes.join(" ")}
        title={
          has
            ? here.map(describe).join("\n")
            : closed
              ? "Closed"
              : unscheduled
                ? "Not scheduled: nobody is on this day at all"
                : undefined
        }
        onClick={
          has
            ? () => {
                setSelectedCell(ref);
                setFocus(null);
              }
            : undefined
        }
      >
        {has && (
          /* Glyph plus count, never colour alone. */
          <span className="problem-mark">
            {kindGlyph(mostSevere(here).kind)} {here.length}
          </span>
        )}
      </td>
    );
  }

  /** The row that opens a panel: its axis in the gutter, its title across the days. */
  function groupRow(label: string, title: string): JSX.Element {
    return (
      <tr className="problem-group">
        <th className="calendar-hour problem-group-label">{label}</th>
        <th className="problem-group-title" colSpan={columns.length}>
          {title}
        </th>
      </tr>
    );
  }

  if (loading) return <div className="page loading">Loading problems...</div>;

  const selectedProblems = selectedCell ? problemsAt(selectedCell) : [];

  return (
    <div className="page">
      <h2>Problems</h2>

      {error && <div className="msg-error">{error}</div>}

      {/* The horizon is a required input, not a filter applied afterwards: a
          problem set without a date range is meaningless. Each segment says how
          many problems it holds and from when, which is the "must I act today"
          question a count alone does not answer. */}
      <div className="horizon-bar">
        {horizons.map((h) => {
          const count = problems.filter(inRange(h)).length;
          const first = earliestDay(problems.filter(inRange(h)));
          const isSelected = selected?.key === h.key;
          return (
            <button
              key={h.key}
              className={
                isSelected ? "horizon-seg horizon-seg-on" : "horizon-seg"
              }
              onClick={() => {
                setSelectedKey(h.key);
                setSelectedCell(null);
                setFocus(null);
              }}
            >
              <span className="horizon-label">
                {isSelected ? "▸ " : ""}
                {h.label}
              </span>
              <span className="horizon-count">
                {count === 0
                  ? "clear"
                  : `${count} problem${count === 1 ? "" : "s"}, from ${first}`}
              </span>
            </button>
          );
        })}
      </div>

      {!selected ? (
        <p className="msg-error">No horizons returned by the server.</p>
      ) : (
        <>
          <div className="detail-section">
            <h3>
              By hour, worker and station — {selected.from} to {selected.to}
            </h3>
            {shown.length === 0 && (
              <p className="msg-success">
                Nothing wrong in this range. Every assignment holds and every
                station meets its minimum.
              </p>
            )}
            {/* Said once, in words, above the grid: "I have not built this period
                yet" is a different situation from a list of things being wrong,
                and it is the one the hatched columns below are reporting. */}
            {unscheduledDays.size > 0 && (
              <p className="msg-warn">
                {unscheduledDays.size === columns.length
                  ? `Nothing is scheduled in this range yet — none of these ` +
                    `${columns.length} days has a single assignment.`
                  : `${unscheduledDays.size} of these ${columns.length} days ` +
                    `have no assignments at all, so their stations are reported ` +
                    `as not scheduled rather than understaffed.`}
              </p>
            )}
            {dayScopedPlaced.length > 0 && (
              <p className="msg-warn">
                {dayScopedPlaced.length} problem(s) affect whole days rather than
                single hours. They appear in the worker and station rows below but
                not in the hour rows.
              </p>
            )}
            {dayScopedUnplaced.length > 0 && (
              <p className="msg-warn">
                {dayScopedUnplaced.length} problem(s) affect whole days and name no
                worker or station, so they are not placed in the grid below.
              </p>
            )}
            <div className="calendar-scroll">
              <table className="calendar-grid problem-grid">
                <thead>
                  <tr>
                    <th className="calendar-hour">Day</th>
                    {columns.map((c) => (
                      <th
                        key={c.day}
                        className={
                          [
                            c.weekend ? "calendar-col-weekend" : "",
                            c.frozen ? "calendar-col-frozen" : "",
                            unscheduledDays.has(c.day)
                              ? "calendar-col-unscheduled"
                              : "",
                          ]
                            .filter(Boolean)
                            .join(" ") || undefined
                        }
                        title={c.frozen ? `${c.day} (past)` : c.day}
                      >
                        {c.label}
                        {c.frozen ? " ❄" : ""}
                        {unscheduledDays.has(c.day) && (
                          /* The day's own problem, stated in words in the header
                             it is about: an empty column otherwise reads as a day
                             with nothing wrong. */
                          <span className="problem-day-badge">
                            {kindGlyph("unscheduled")} not scheduled
                          </span>
                        )}
                      </th>
                    ))}
                  </tr>
                </thead>

                {/* Panel 1: hours down the side. */}
                <tbody className="problem-panel" data-panel="hour">
                  {groupRow("Hour", "By hour")}
                  {hours.map((h) => (
                    <tr key={h}>
                      <td className="calendar-hour">{pad2(h)}:00</td>
                      {columns.map((c) =>
                        renderCell(
                          { panel: "hour", row: h, day: c.day },
                          c,
                          !c.open.has(h)
                        )
                      )}
                    </tr>
                  ))}
                </tbody>

                {/* Panel 2: one row per worker. Understaffing names nobody, so it
                    never appears here — it is a station fact and lives below. */}
                <tbody className="problem-panel" data-panel="worker">
                  {groupRow(
                    "Worker",
                    `By worker — ${workerRows.length} worker${
                      workerRows.length === 1 ? "" : "s"
                    }`
                  )}
                  {workerRows.length === 0 && (
                    <tr>
                      <td className="text-muted" colSpan={columns.length + 1}>
                        No active workers.
                      </td>
                    </tr>
                  )}
                  {workerRows.map((w) => (
                    <tr key={w.id}>
                      <td
                        className={
                          "calendar-hour problem-row-label" +
                          (w.active ? "" : " problem-row-inactive")
                        }
                        title={w.active ? w.name : `${w.name} is inactive`}
                      >
                        {w.name}
                        {w.active ? "" : " (inactive)"}
                      </td>
                      {columns.map((c) =>
                        renderCell({ panel: "worker", row: w.id, day: c.day }, c, false)
                      )}
                    </tr>
                  ))}
                </tbody>

                {/* Panel 3: one row per station, grouped by zone. */}
                <tbody className="problem-panel" data-panel="station">
                  {groupRow(
                    "Station",
                    `By station — ${zoneGroups.length} zone${
                      zoneGroups.length === 1 ? "" : "s"
                    }`
                  )}
                  {zoneGroups.length === 0 && (
                    <tr>
                      <td className="text-muted" colSpan={columns.length + 1}>
                        No stations defined.
                      </td>
                    </tr>
                  )}
                  {zoneGroups.map((g) => (
                    <ZoneRows
                      key={g.zone ?? " unassigned"}
                      group={g}
                      columns={columns}
                      renderCell={renderCell}
                    />
                  ))}
                </tbody>
              </table>
            </div>
            <div className="calendar-legend">
              <span>! violates a hard rule</span>
              <span>&#9675; not scheduled: nobody on that day at all</span>
              <span>&#9660; understaffed, below the station's minimum</span>
              <span>Number: how many problems in that cell</span>
              <span>Hatched column: the day is not scheduled</span>
              <span>Tinted column: weekend</span>
              <span>&#10052; already past</span>
            </div>
          </div>

          <div className="detail-section">
            <h3>
              {selectedCell
                ? `${captionFor(selectedCell)} — ` +
                  `${selectedProblems.length} problem(s)`
                : "Details"}
            </h3>
            {!selectedCell ? (
              <p className="text-muted">
                Click a marked cell in any panel to see what is wrong there.
              </p>
            ) : (
              <>
                <p className="text-muted">
                  Click a problem to outline its worker, station and hour in the
                  panels above.
                </p>
                <ul className="problem-list">
                  {selectedProblems.map((p, i) => (
                    <li
                      key={`${p.kind}|${p.worker}|${p.station}|${i}`}
                      className={
                        focus === p ? "problem-item problem-item-focus" : "problem-item"
                      }
                      onClick={() => setFocus(focus === p ? null : p)}
                    >
                      {focus === p ? "▸ " : ""}
                      <strong>{kindLabel(p.kind)}:</strong> {describe(p)}
                    </li>
                  ))}
                </ul>
                {focus && (
                  /* Three outlined cells with no words is a puzzle, and an outline
                     colour is not something every reader can tell apart. */
                  <p className="problem-focus-caption">Showing: {whereIs(focus)}</p>
                )}
                <button
                  className="btn btn-sm btn-secondary"
                  onClick={() => {
                    setSelectedCell(null);
                    setFocus(null);
                  }}
                >
                  Close
                </button>
              </>
            )}
          </div>
        </>
      )}
    </div>
  );
}

/**
 * One zone of the station panel: a heading row naming the zone, then a row per
 * station. A fragment rather than its own tbody so the three panels stay three
 * row groups, and so a zone heading cannot be mistaken for a panel heading.
 */
function ZoneRows({
  group,
  columns,
  renderCell,
}: {
  group: ZoneGroup;
  columns: Column[];
  renderCell: (ref: CellRef, col: Column, closed: boolean) => JSX.Element;
}) {
  return (
    <>
      <tr className="problem-zone">
        <th className="problem-zone-title" colSpan={columns.length + 1}>
          {group.zone === null ? "Unassigned" : `Zone: ${group.zone}`}
          <span className="problem-zone-count">
            {" "}
            &middot; {group.stations.length} station
            {group.stations.length === 1 ? "" : "s"}
          </span>
        </th>
      </tr>
      {group.stations.map((s) => (
        <tr key={s.id}>
          <td className="calendar-hour problem-row-label">{s.name}</td>
          {columns.map((c) =>
            renderCell({ panel: "station", row: s.id, day: c.day }, c, false)
          )}
        </tr>
      ))}
    </>
  );
}
