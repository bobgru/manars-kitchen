/**
 * Drives the problem view at `/` in headless Chromium: the horizon control and
 * its marks, the three panels (by hour, by worker, by station grouped by zone), a
 * marked cell in each, the detail pane, and the clear state.
 *
 * Prerequisites, none of which this script manages:
 *
 *   1. A database seeded with the demo, which is the only fixture that puts
 *      anything in the calendar:
 *
 *        stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay
 *        sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);"
 *        rm -f /tmp/mk-dash.db /tmp/mk-dash.db-wal /tmp/mk-dash.db-shm
 *        cp demo-db/demo.db /tmp/mk-dash.db
 *
 *      **Checkpoint before copying** or the copy has an empty calendar.
 *
 *      Note what the demo gives this page: its committed calendar is April 2026,
 *      which **no horizon covers**, so nobody is on any day of the current or next
 *      pay period. The opening view is therefore one "not scheduled" day per
 *      column and **no** hour cells — understaffing presupposes an attempt to
 *      staff, so an untouched day is reported once instead of 45 times (ADR 0007).
 *      This script asserts that baseline, then commits a draft over the current
 *      period, which is what turns the day badges into per-hour problems.
 *   2. `stack exec manars-server -- /tmp/mk-dash.db` on port 8080.
 *   3. `npm run dev` in web/ on port 5173.
 *   4. `npx playwright install chromium` once.
 *
 * It mutates the database, so re-run it against a fresh copy.
 */
import { chromium } from "playwright";
import { mkdir } from "node:fs/promises";

const SHOTS = new URL("./screenshots/", import.meta.url).pathname;
await mkdir(SHOTS, { recursive: true });

const errors = [];
const browser = await chromium.launch({ args: ["--no-sandbox"] });
const page = await (await browser.newContext()).newPage();
page.on("console", (m) => {
  if (m.type() === "error") errors.push(m.text());
});
page.on("pageerror", (e) => errors.push(String(e)));

const step = async (name) => {
  await page.screenshot({ path: `${SHOTS}${name}.png`, fullPage: true });
  console.log(`--- ${name}`);
};

const shotOf = async (locator, name) => {
  await locator.screenshot({ path: `${SHOTS}${name}.png` });
  console.log(`--- ${name}`);
};

const fail = (msg) => {
  errors.push(`ASSERTION: ${msg}`);
  console.log(`ASSERTION FAILED: ${msg}`);
};

/** Call the API as the logged-in admin, from inside the page. */
const api = (path, init) =>
  page.evaluate(
    async ([p, i]) => {
      const token = sessionStorage.getItem("token");
      const resp = await fetch(p, {
        ...i,
        headers: { ...(i?.headers ?? {}), Authorization: `Bearer ${token}` },
      });
      const text = await resp.text();
      // Error bodies are plain text; do not let one turn a failed assertion into
      // an uncaught exception.
      let body = null;
      try {
        body = text ? JSON.parse(text) : null;
      } catch {
        body = text;
      }
      return { status: resp.status, body };
    },
    [path, init]
  );

await page.goto("http://localhost:5173/", { waitUntil: "domcontentloaded" });
await page.getByLabel("Username").fill("admin");
await page.getByLabel("Password").fill("admin");
await page.getByRole("button", { name: /log ?in/i }).click();
await page.getByRole("heading", { name: "Problems" }).waitFor();
console.log("logged in, landed on the problem view");

// --- The horizon control ----------------------------------------------------
const segs = page.locator(".horizon-seg");
const segCount = await segs.count();
if (segCount !== 3) fail(`expected 3 horizon segments, got ${segCount}`);
await page.getByText(/Today/).first().waitFor();
await page.locator("table.calendar-grid").waitFor();

// Three panels, three row groups of one table, so the day columns are shared and
// one date lines up vertically. Each opens with its title in words.
const panels = page.locator("tbody.problem-panel");
const panelCount = await panels.count();
if (panelCount !== 3) fail(`expected 3 panels, got ${panelCount}`);
for (const title of [/^By hour$/, /^By worker/, /^By station/]) {
  if ((await page.locator(".problem-group-title").filter({ hasText: title }).count()) !== 1) {
    fail(`missing panel title ${title}`);
  }
}
// The demo restaurant labels zones; busboy is left out so "Unassigned" shows too.
for (const zone of ["Zone: hot line", "Zone: front", "Unassigned"]) {
  if ((await page.locator(".problem-zone-title").filter({ hasText: zone }).count()) !== 1) {
    fail(`missing zone heading "${zone}"`);
  }
}
const zoneRows = await page.locator("tr.problem-zone").count();
const workerRows = await page.locator('tbody[data-panel="worker"] tr').count() - 1;
console.log(`3 panels: ${workerRows} worker rows, ${zoneRows} zone groups`);
await step("p01-initial");

// The demo's committed calendar is April 2026, which no horizon covers, so nobody
// is on any day in range. Each such day is reported once as "not scheduled" and
// its station-slots are not reported understaffed — ADR 0007. So the baseline is
// day badges and an empty grid, not 630 marks.
const initialBadges = await page.locator(".problem-day-badge").count();
if (initialBadges === 0) fail("no 'not scheduled' badge on a period nobody staffed");
const initialMarks = await page.locator(".problem-mark").count();
if (initialMarks !== 0) {
  fail(`an unscheduled day should have no hour cells, saw ${initialMarks}`);
}
// The badge says it in words, not by colour or hatching alone.
await page.getByText(/not scheduled/).first().waitFor();
console.log(`${initialBadges} days reported as not scheduled, ${initialMarks} marks`);
await shotOf(page.locator(".horizon-bar"), "p02-horizon-bar");

// Every segment reports a count, which is what makes the control a mark as well
// as a selector.
for (const key of ["Today", "2026-"]) {
  const seg = segs.filter({ hasText: key }).first();
  const text = await seg.textContent();
  if (!/problem|clear/.test(text)) {
    fail(`segment "${key}" reports neither a count nor "clear": ${text}`);
  }
}

// --- Switching horizon is a filter, not a refetch ---------------------------
await segs.filter({ hasText: "Today" }).click();
await page.getByRole("heading", { name: /^By hour/ }).waitFor();
const todayCols = await page.locator("thead th").count();
// One hour gutter plus exactly one day column.
if (todayCols !== 2) fail(`Today should show one day column, saw ${todayCols - 1}`);
await step("p03-today");

// --- Staffing the period changes the answer, live over SSE ------------------
const horizons = await api("/api/horizons");
const current = horizons.body.find((h) => h.key === "current-period");
const today = horizons.body.find((h) => h.key === "today");
console.log(`current period is ${current.from}..${current.to}, today ${today.from}`);
await segs.filter({ hasText: current.label }).click();
await page.getByRole("heading", { name: /^By hour/ }).waitFor();

// From today, not from the period's start: dates before today are frozen, and a
// REST caller cannot force past the freeze line, so a draft over the whole
// period is a 409 on every day of the period but its first.
const created = await api("/api/drafts", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ dateFrom: today.from, dateTo: current.to }),
});
if (created.status !== 200) fail(`draft create returned ${created.status}`);
const did = created.body.id;
await api(`/api/drafts/${did}/generate`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({}),
});
const committed = await api(`/api/drafts/${did}/commit`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ note: "for the dashboard driver" }),
});
if (committed.status !== 204) fail(`commit returned ${committed.status}`);

// The commit publishes a calendar event and the page reloads itself: the staffed
// days lose their "not scheduled" badge. Asserting on that rather than reloading
// by hand, because live refresh is part of what this page promises.
await page.waitForFunction(
  (n) => document.querySelectorAll(".problem-day-badge").length < n,
  initialBadges,
  { timeout: 30000 }
);

// --- The sick call ----------------------------------------------------------
// Whether the scheduler leaves a station short over the remaining days depends
// on the weekday this runs, so manufacture a problem that does not: approve an
// absence for the busiest committed worker. That invalidates their assignments
// without touching the calendar, which is the case ADR 0004 is built around, and
// the page must pick it up from the absence event alone.
const committedCal = await api(`/api/calendar?from=${today.from}&to=${current.to}`);
const perWorker = new Map();
for (const a of committedCal.body) perWorker.set(a.worker, (perWorker.get(a.worker) ?? 0) + 1);
const [sickId, sickCount] = [...perWorker.entries()].sort((x, y) => y[1] - x[1])[0] ?? [];
if (sickId === undefined) fail("the committed calendar has no assignments over REST");
const typeCreated = await api("/api/absence-types", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ name: "e2e-sick", countsAgainstAllowance: false }),
});
if (typeCreated.status !== 204) fail(`absence-type create returned ${typeCreated.status}`);
const exported = await api("/api/export");
const sickType = exported.body.absenceTypes.find((t) => t.name === "e2e-sick");
const requested = await api("/api/absences", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ workerId: sickId, typeId: sickType.id, from: today.from, to: current.to }),
});
if (requested.status !== 200) fail(`absence request returned ${requested.status}: ${requested.body}`);
const approved = await api(`/api/absences/${requested.body.id}/approve`, { method: "POST" });
if (approved.status !== 204) fail(`absence approve returned ${approved.status}`);
console.log(`worker ${sickId} called in sick with ${sickCount} committed assignments`);

// Staffing the period is what converts "not scheduled" into per-hour problems, and
// the sick call guarantees there are some: every one of that worker's hours is
// now an absence-conflict violation, naming a worker, a station and a slot.
await page.waitForFunction(
  () => document.querySelectorAll(".problem-mark").length > 0,
  null,
  { timeout: 30000 }
);
const afterMarks = await page.locator(".problem-mark").count();
const afterBadges = await page.locator(".problem-day-badge").count();
console.log(
  `after committing: ${afterBadges} unscheduled days (was ${initialBadges}), ` +
    `${afterMarks} marked cells (was ${initialMarks})`
);
if (afterBadges >= initialBadges) {
  fail(`staffing the period should clear day badges (${initialBadges} -> ${afterBadges})`);
}
await step("p04-after-staffing");
await shotOf(page.locator(".horizon-bar"), "p05-horizon-bar-after");

// The worker and station panels are projections of the same set: one mark per
// (worker, day) and per (station, day) pair that any problem in range names.
const probs = await api(
  `/api/problems?from=${current.from}&to=${current.to}`
);
const dayOf = (p) => (p.scope.kind === "slot" ? p.scope.slot.date : p.scope.day);
const pairs = (field) =>
  new Set(probs.body.filter((p) => p[field] !== null).map((p) => `${p[field]}|${dayOf(p)}`)).size;
const workerMarks = await page.locator('tbody[data-panel="worker"] .problem-mark').count();
const stationMarks = await page.locator('tbody[data-panel="station"] .problem-mark').count();
console.log(
  `worker panel: ${workerMarks} marks for ${pairs("worker")} (worker, day) pairs; ` +
    `station panel: ${stationMarks} marks for ${pairs("station")} (station, day) pairs`
);
if (workerMarks !== pairs("worker")) fail("worker panel marks disagree with the problem set");
if (stationMarks !== pairs("station")) fail("station panel marks disagree with the problem set");
if (workerMarks === 0) fail("the sick call should mark the worker panel");
if (stationMarks === 0) fail("the sick call should mark the station panel");

// A cell in the station panel opens the same detail pane, captioned by row and day.
await page.locator('tbody[data-panel="station"] .problem-mark').first().click();
await page.getByRole("heading", { name: /on \d{4}-\d{2}-\d{2} — \d+ problem\(s\)/ }).waitFor();
await shotOf(page.locator('tbody[data-panel="station"]'), "p05b-station-panel");
await shotOf(page.locator('tbody[data-panel="worker"]'), "p05c-worker-panel");

// Picking one problem outlines its cells across the panels and says where it is
// in words — a violation names a worker, a station and an hour, so all three.
await page.locator(".problem-item").first().click();
await page.getByText(/^Showing: /).waitFor();
const focused = await page.locator(".problem-cell-focus").count();
if (focused !== 3) fail(`a violation should outline 3 cells across the panels, got ${focused}`);
console.log(`focused problem outlines ${focused} cells`);
await step("p05d-cross-panel-focus");
await page.getByRole("button", { name: "Close" }).click();

// --- The detail pane --------------------------------------------------------
// Only reachable now: an unscheduled day has no cells to open.
await page.locator(".problem-mark").first().click();
await page.getByRole("heading", { name: /\d+ problem\(s\)/ }).waitFor();
const items = await page.locator(".detail-section li").count();
if (items === 0) fail("detail pane opened with no problems listed");
const selectedCells = await page.locator(".problem-cell-selected").count();
if (selectedCells !== 1) {
  fail(`expected exactly one selected cell, got ${selectedCells}`);
}
// The pane says what is wrong in words, not just a glyph.
await page.getByText(/staffed|scheduled|:/).first().waitFor();
console.log(`detail pane lists ${items} problem(s)`);
await step("p06-detail-pane");
await shotOf(page.locator(".detail-section").last(), "p07-detail-section");

await page.getByRole("button", { name: "Close" }).click();
await page.getByText(/Click a marked cell/).waitFor();

console.log(
  errors.length ? `CONSOLE ERRORS:\n${errors.join("\n")}` : "no unexpected console errors"
);
await browser.close();
if (errors.length) process.exit(1);
