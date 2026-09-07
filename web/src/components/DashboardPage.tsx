import { useState, useEffect, useCallback, useMemo } from "react";
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
import {
  fetchNameMaps,
  fetchFreezeLine,
  type NameMaps,
} from "../api/calendar";
import { useEntityEvents } from "../hooks/useSSE";
import { buildColumns, cellKey, pad2 } from "../lib/grid";

const EMPTY_NAMES: NameMaps = { workers: new Map(), stations: new Map() };

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
 * Only the hours projection exists so far. The worker and station views are piece
 * 4 of item 2 in `docs/STATUS.md`; they share these day columns so that one date
 * lines up vertically across all three panels.
 */
export default function DashboardPage() {
  const [horizons, setHorizons] = useState<Horizon[]>([]);
  const [selectedKey, setSelectedKey] = useState("current-period");
  const [problems, setProblems] = useState<Problem[]>([]);
  const [names, setNames] = useState<NameMaps>(EMPTY_NAMES);
  const [freezeLine, setFreezeLine] = useState("");

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedCell, setSelectedCell] = useState<null | {
    day: string;
    hour: number;
  }>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      // The horizons decide the range to fetch, so they come first. Names and the
      // freeze line only decorate the grid and fall back rather than failing it.
      const [hs, maps, freeze] = await Promise.all([
        fetchHorizons(),
        fetchNameMaps().catch(() => EMPTY_NAMES),
        fetchFreezeLine().catch(() => ""),
      ]);
      setHorizons(hs);
      setNames(maps);
      setFreezeLine(freeze);
      if (hs.length === 0) {
        setProblems([]);
        return;
      }
      const unionFrom = hs.reduce((a, h) => (h.from < a ? h.from : a), hs[0].from);
      const unionTo = hs.reduce((a, h) => (h.to > a ? h.to : a), hs[0].to);
      setProblems(await fetchProblems(unionFrom, unionTo));
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

  // Day-scoped problems cannot sit in an hour cell. None exist yet; compromises
  // in piece 5 will be the first, and this reports them rather than dropping them
  // silently.
  const dayScoped = useMemo(
    () => shown.filter((p) => problemHour(p) === null),
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

  function workerName(id: number | null): string {
    if (id === null) return "nobody";
    return names.workers.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number | null): string {
    if (id === null) return "no station";
    return names.stations.get(id) ?? `station ${id}`;
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
    return `${kindLabel(p.kind)} — ${stationName(p.station)}`;
  }

  if (loading) return <div className="page loading">Loading problems...</div>;

  const selectedProblems = selectedCell
    ? (byCell.get(cellKey(selectedCell.day, selectedCell.hour)) ?? [])
    : [];

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
              By hour — {selected.from} to {selected.to}
            </h3>
            {shown.length === 0 && (
              <p className="msg-success">
                Nothing wrong in this range. Every assignment holds and every
                station meets its minimum.
              </p>
            )}
            {dayScoped.length > 0 && (
              <p className="msg-warn">
                {dayScoped.length} problem(s) affect whole days rather than single
                hours and are not placed in the grid below.
              </p>
            )}
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
                        title={c.frozen ? `${c.day} (past)` : c.day}
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
                        const here = byCell.get(cellKey(c.day, h));
                        const closed = !c.open.has(h);
                        const classes = ["problem-cell"];
                        if (c.weekend) classes.push("calendar-col-weekend");
                        if (closed && !here) classes.push("calendar-cell-closed");
                        const isOpen =
                          selectedCell?.day === c.day && selectedCell?.hour === h;
                        if (isOpen) classes.push("problem-cell-selected");
                        if (here) {
                          classes.push(`problem-cell-${mostSevere(here).kind}`);
                        }
                        return (
                          <td
                            key={c.day}
                            className={classes.join(" ")}
                            title={
                              here
                                ? here.map(describe).join("\n")
                                : closed
                                  ? "Closed"
                                  : undefined
                            }
                            onClick={
                              here
                                ? () => setSelectedCell({ day: c.day, hour: h })
                                : undefined
                            }
                          >
                            {here && (
                              /* Glyph plus count, never colour alone. */
                              <span className="problem-mark">
                                {kindGlyph(mostSevere(here).kind)} {here.length}
                              </span>
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
              <span>! violates a hard rule</span>
              <span>&#9660; understaffed, below the station's minimum</span>
              <span>Number: how many problems in that hour</span>
              <span>Tinted column: weekend</span>
              <span>&#10052; already past</span>
            </div>
          </div>

          <div className="detail-section">
            <h3>
              {selectedCell
                ? `${selectedCell.day} at ${pad2(selectedCell.hour)}:00 — ` +
                  `${selectedProblems.length} problem(s)`
                : "Details"}
            </h3>
            {!selectedCell ? (
              <p className="text-muted">
                Click a marked cell to see what is wrong in that hour.
              </p>
            ) : (
              <>
                <ul>
                  {selectedProblems.map((p, i) => (
                    <li key={`${p.kind}|${p.worker}|${p.station}|${i}`}>
                      <strong>{kindLabel(p.kind)}:</strong> {describe(p)}
                    </li>
                  ))}
                </ul>
                <button
                  className="btn btn-sm btn-secondary"
                  onClick={() => setSelectedCell(null)}
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
