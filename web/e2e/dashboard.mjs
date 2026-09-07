/**
 * Drives the problem view at `/` in headless Chromium: the horizon control and
 * its marks, the hours grid, a marked cell, the detail pane, and the clear state.
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
 *      which **no horizon covers**, so every station-slot in the current and next
 *      pay periods is unstaffed and the opening view is wall-to-wall
 *      understaffing — around 630 problems per fortnight. That is the fixture,
 *      not the page. This script asserts on that baseline and then commits a
 *      draft over the current period to prove the count comes down.
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
      return { status: resp.status, body: text ? JSON.parse(text) : null };
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
await step("p01-initial");

// The demo's committed calendar is April 2026, which no horizon covers. So every
// station-slot in range is unstaffed and the whole grid is understaffing. That is
// the honest baseline for this fixture, and it is the state docs/STATUS.md
// discusses under "understaffing presupposes an attempt to staff".
const initialMarks = await page.locator(".problem-mark").count();
if (initialMarks === 0) fail("no marked cells on a range with nothing scheduled");
const initialUnderstaffed = await page.locator(".problem-cell-understaffed").count();
if (initialUnderstaffed === 0) fail("nothing rendered as understaffed");
console.log(`${initialMarks} marked cells, ${initialUnderstaffed} understaffed`);
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

// --- The detail pane --------------------------------------------------------
await page.locator(".problem-mark").first().click();
await page.getByRole("heading", { name: /\d+ problem\(s\)/ }).waitFor();
const items = await page.locator(".detail-section li").count();
if (items === 0) fail("detail pane opened with no problems listed");
const selectedCells = await page.locator(".problem-cell-selected").count();
if (selectedCells !== 1) {
  fail(`expected exactly one selected cell, got ${selectedCells}`);
}
// The pane says what is wrong in words, not just a glyph.
await page.getByText(/staffed/).first().waitFor();
console.log(`detail pane lists ${items} problem(s)`);
await step("p03-detail-pane");
await shotOf(page.locator(".detail-section").last(), "p04-detail-section");

await page.getByRole("button", { name: "Close" }).click();
await page.getByText(/Click a marked cell/).waitFor();

// --- Switching horizon is a filter, not a refetch ---------------------------
await segs.filter({ hasText: "Today" }).click();
await page.getByRole("heading", { name: /^By hour/ }).waitFor();
const todayCols = await page.locator("thead th").count();
// One hour gutter plus exactly one day column.
if (todayCols !== 2) fail(`Today should show one day column, saw ${todayCols - 1}`);
await step("p05-today");

// --- Staffing the period changes the answer, live over SSE ------------------
const horizons = await api("/api/horizons");
const current = horizons.body.find((h) => h.key === "current-period");
console.log(`current period is ${current.from}..${current.to}`);
await segs.filter({ hasText: current.label }).click();
await page.getByRole("heading", { name: /^By hour/ }).waitFor();

const created = await api("/api/drafts", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ dateFrom: current.from, dateTo: current.to }),
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

// The commit publishes a calendar event and the page reloads itself. Asserting on
// that rather than reloading by hand, because live refresh is part of what this
// page promises: an approved absence or a revoked skill changes the answer without
// anyone touching the calendar.
await page.waitForFunction(
  (before) => document.querySelectorAll(".problem-mark").length !== before,
  initialMarks,
  { timeout: 20000 }
);
const afterMarks = await page.locator(".problem-mark").count();
console.log(`marked cells went ${initialMarks} -> ${afterMarks} after committing`);
if (afterMarks >= initialMarks) {
  fail(`staffing the period should reduce marks (${initialMarks} -> ${afterMarks})`);
}
await step("p06-after-staffing");
await shotOf(page.locator(".horizon-bar"), "p07-horizon-bar-after");

console.log(
  errors.length ? `CONSOLE ERRORS:\n${errors.join("\n")}` : "no unexpected console errors"
);
await browser.close();
if (errors.length) process.exit(1);
