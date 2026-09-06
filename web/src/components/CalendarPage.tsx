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
import ScheduleGrid from "./ScheduleGrid";
import { formatDay, parseDay, rangeProblem } from "../lib/grid";

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
            <ScheduleGrid
              layout="hours-days"
              assignments={shown}
              from={gridFrom}
              to={gridTo}
              names={names}
              freezeLine={freezeLine}
            />
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
