import { useState, useEffect, useCallback, useMemo } from "react";
import { useSearchParams } from "react-router";
import {
  fetchCalendar,
  fetchCalendarHistory,
  fetchCalendarCommit,
  fetchFreezeLine,
  fetchNameMaps,
  type Assignment,
  type CalendarCommit,
  type NameMaps,
} from "../api/calendar";
import { useEntityEvents } from "../hooks/useSSE";

// One column per day, so a very wide range is unreadable as well as slow.
const MAX_DAYS = 92;

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** A day column: its open hours, plus whether it is a weekend or frozen. */
interface Column {
  day: string;
  label: string;
  weekend: boolean;
  frozen: boolean;
  open: Set<number>;
}

function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

function formatDay(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** Parse YYYY-MM-DD as a local-midnight Date, or null if malformed. */
function parseDay(s: string): Date | null {
  if (!DAY_RE.test(s)) return null;
  const [y, m, d] = s.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  const roundTrips =
    dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d;
  return roundTrips ? dt : null;
}

function coerceDay(raw: string | null, fallback: string): string {
  return raw && parseDay(raw) ? raw : fallback;
}

function currentMonthRange(): { from: string; to: string } {
  const now = new Date();
  return {
    from: formatDay(new Date(now.getFullYear(), now.getMonth(), 1)),
    to: formatDay(new Date(now.getFullYear(), now.getMonth() + 1, 0)),
  };
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
function rangeProblem(from: string, to: string): string {
  const f = parseDay(from);
  const t = parseDay(to);
  if (!f || !t) return "Pick a valid from and to date.";
  if (f > t) return "The from date must not be after the to date.";
  const days = Math.round((t.getTime() - f.getTime()) / 86400000) + 1;
  if (days > MAX_DAYS) return `Range covers ${days} days; pick ${MAX_DAYS} or fewer.`;
  return "";
}

function buildColumns(from: string, to: string, freezeLine: string): Column[] {
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

function slotHour(a: Assignment): number {
  return Number(a.slot.start.slice(0, 2));
}

function cellKey(day: string, hour: number): string {
  return `${day}|${hour}`;
}

export default function CalendarPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const defaults = useMemo(currentMonthRange, []);
  const from = coerceDay(searchParams.get("from"), defaults.from);
  const to = coerceDay(searchParams.get("to"), defaults.to);

  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [history, setHistory] = useState<CalendarCommit[]>([]);
  const [freezeLine, setFreezeLine] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const [names, setNames] = useState<NameMaps>({
    workers: new Map(),
    stations: new Map(),
  });

  const [snapshot, setSnapshot] = useState<null | {
    commit: CalendarCommit;
    assignments: Assignment[];
  }>(null);

  const load = useCallback(async () => {
    try {
      setError("");
      // An out-of-bounds range is reported in place of the grid, not as an error.
      if (rangeProblem(from, to)) return;
      const [slice, commits, freeze] = await Promise.all([
        fetchCalendar(from, to),
        fetchCalendarHistory(),
        fetchFreezeLine(),
      ]);
      setAssignments(slice);
      setHistory(commits);
      setFreezeLine(freeze);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, [from, to]);

  const loadNames = useCallback(async () => {
    try {
      setNames(await fetchNameMaps());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  useEffect(() => {
    loadNames();
  }, [loadNames]);

  // Committing a draft is what rewrites the calendar, so watch both topics.
  useEntityEvents("calendar", load);
  useEntityEvents("draft", load);
  useEntityEvents("worker", loadNames);
  useEntityEvents("station", loadNames);

  // A historical snapshot carries its own range; the live view uses the URL range.
  const gridFrom = snapshot ? snapshot.commit.dateFrom : from;
  const gridTo = snapshot ? snapshot.commit.dateTo : to;
  const shown = snapshot ? snapshot.assignments : assignments;
  const problem = rangeProblem(gridFrom, gridTo);

  const columns = useMemo(
    () => buildColumns(gridFrom, gridTo, freezeLine),
    [gridFrom, gridTo, freezeLine]
  );

  // Index once per fetch: a month grid asks ~360 questions of this map.
  const byCell = useMemo(() => {
    const index = new Map<string, Assignment[]>();
    for (const a of shown) {
      const key = cellKey(a.slot.date, slotHour(a));
      const bucket = index.get(key);
      if (bucket) bucket.push(a);
      else index.set(key, [a]);
    }
    return index;
  }, [shown]);

  const hours = useMemo(() => {
    const set = new Set<number>();
    for (const c of columns) for (const h of c.open) set.add(h);
    // Station-specific hours can fall outside the defaults; never hide a slot.
    for (const a of shown) set.add(slotHour(a));
    return Array.from(set).sort((x, y) => x - y);
  }, [columns, shown]);

  function changeRange(next: { from?: string; to?: string }) {
    setSnapshot(null);
    setSearchParams({ from: next.from ?? from, to: next.to ?? to });
  }

  async function handleViewSnapshot(commit: CalendarCommit) {
    try {
      setError("");
      setSnapshot({ commit, assignments: await fetchCalendarCommit(commit.id) });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  function workerName(id: number): string {
    return names.workers.get(id) ?? `worker ${id}`;
  }

  function stationName(id: number): string {
    return names.stations.get(id) ?? `station ${id}`;
  }

  if (loading) return <div className="page loading">Loading calendar...</div>;

  return (
    <div className="page">
      <h2>Calendar</h2>

      {error && <div className="msg-error">{error}</div>}

      <div className="calendar-toolbar">
        <label>
          From{" "}
          <input
            className="form-input"
            type="date"
            value={from}
            onChange={(e) =>
              e.target.value && changeRange({ from: e.target.value })
            }
          />
        </label>
        <label>
          To{" "}
          <input
            className="form-input"
            type="date"
            value={to}
            onChange={(e) => e.target.value && changeRange({ to: e.target.value })}
          />
        </label>
        <button
          className="btn btn-sm btn-secondary"
          onClick={() => changeRange({ from: defaults.from, to: defaults.to })}
        >
          This month
        </button>
        <span className="text-muted">
          {shown.length} assignment{shown.length === 1 ? "" : "s"}
        </span>
      </div>

      <div className="detail-section">
        <h3>
          {snapshot
            ? `Snapshot before commit #${snapshot.commit.id}`
            : "Committed calendar"}
        </h3>
        {snapshot && (
          <div className="action-bar">
            <span className="text-muted">
              {snapshot.commit.dateFrom} to {snapshot.commit.dateTo}, as it stood
              before {snapshot.commit.committedAt}.
            </span>
            <button
              className="btn btn-sm btn-secondary"
              onClick={() => setSnapshot(null)}
            >
              Back to live calendar
            </button>
          </div>
        )}

        {problem ? (
          <p className="msg-error">{problem}</p>
        ) : (
          <>
            {shown.length === 0 && (
              <p className="text-muted">
                Nothing is committed in {gridFrom} to {gridTo}.
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
                            {chips?.map((a) => (
                              <span
                                className="calendar-chip"
                                key={`${a.worker}|${a.station}`}
                              >
                                {workerName(a.worker)}{" "}
                                <span className="calendar-chip-station">
                                  {stationName(a.station)}
                                </span>
                              </span>
                            ))}
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
            </div>
          </>
        )}
      </div>

      <div className="detail-section">
        <h3>Commit history</h3>
        {history.length === 0 ? (
          <p className="text-muted">No commits yet.</p>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Committed at</th>
                <th>Range</th>
                <th>Note</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {history.map((c) => (
                <tr key={c.id}>
                  <td>{c.id}</td>
                  <td>{c.committedAt}</td>
                  <td>
                    {c.dateFrom} to {c.dateTo}
                  </td>
                  <td>{c.note || <span className="text-muted">none</span>}</td>
                  <td>
                    <button
                      className="btn btn-sm"
                      onClick={() => handleViewSnapshot(c)}
                      disabled={snapshot?.commit.id === c.id}
                    >
                      {snapshot?.commit.id === c.id
                        ? "Viewing"
                        : "View snapshot"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
