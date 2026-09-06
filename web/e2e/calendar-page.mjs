/**
 * Drives /calendar in headless Chromium: the live grid over a populated month,
 * the commit history, a historical snapshot, and the range guard.
 *
 * This exists because `/calendar` had never been run against a live server —
 * `docs/STATUS.md` carried that caveat from the day it was written — and because
 * the grid it draws now comes from a shared `ScheduleGrid` that a draft also
 * uses. A regression here would be invisible to `tsc`.
 *
 * Prerequisites, none of which this script manages:
 *
 *   1. A database seeded with the demo, which is what puts anything in the
 *      calendar at all — a fresh database has zero rows in `calendar_assignments`
 *      and `calendar_commits`:
 *
 *        stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay
 *        sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);"
 *        rm -f /tmp/mk-detail.db /tmp/mk-detail.db-wal /tmp/mk-detail.db-shm
 *        cp demo-db/demo.db /tmp/mk-detail.db
 *
 *      **Checkpoint before copying.** The demo leaves most of what it wrote in
 *      `demo-db/demo.db-wal`; copy the `.db` alone and you get a database with
 *      zero calendar rows, which reads as a broken page rather than a bad
 *      fixture.
 *
 *      The demo commits five drafts over April 2026, which is the month asserted
 *      on below.
 *   2. `stack exec manars-server -- /tmp/mk-detail.db` on port 8080.
 *   3. `npm run dev` in web/ on port 5173.
 *   4. `npx playwright install chromium` once.
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

const fail = (msg) => {
  errors.push(`ASSERTION: ${msg}`);
  console.log(`ASSERTION FAILED: ${msg}`);
};

await page.goto("http://localhost:5173/", { waitUntil: "domcontentloaded" });
await page.getByLabel("Username").fill("admin");
await page.getByLabel("Password").fill("admin");
await page.getByRole("button", { name: /log ?in/i }).click();
await page.getByRole("link", { name: "Calendar" }).waitFor();
console.log("logged in");

// --- The live grid over a month the demo committed into ----------------------
await page.goto("http://localhost:5173/calendar?from=2026-04-01&to=2026-04-30", {
  waitUntil: "domcontentloaded",
});
// "Calendar" alone also matches the "Committed calendar" section heading.
await page.getByRole("heading", { name: "Calendar", exact: true }).waitFor();
await page.locator("table.calendar-grid").waitFor();
const chips = await page.locator(".calendar-chip").count();
if (chips === 0) fail("April 2026 rendered no chips; is the database demo-seeded?");
console.log(`grid shows ${chips} chips`);
// Every date in April 2026 is behind the freeze line, so the whole header is
// marked; the mark is a snowflake, not a colour.
const frozen = await page.locator("th.calendar-col-frozen").count();
if (frozen === 0) fail("no column marked frozen in a month that is entirely past");
await step("c01-live-month");

// --- Commit history and a snapshot ------------------------------------------
await page.getByRole("heading", { name: "Commit history" }).waitFor();
const history = await page.getByRole("button", { name: "View snapshot" }).count();
if (history === 0) fail("no commits in history; is the database demo-seeded?");
await page.getByRole("button", { name: "View snapshot" }).first().click();
await page.getByRole("heading", { name: /Snapshot before commit #/ }).waitFor();
await step("c02-snapshot");
await page.getByRole("button", { name: "Back to live calendar" }).click();
await page.getByRole("heading", { name: "Committed calendar" }).waitFor();

// --- The range guard, which now lives in ScheduleGrid -----------------------
await page.goto("http://localhost:5173/calendar?from=2026-01-01&to=2026-12-31", {
  waitUntil: "domcontentloaded",
});
await page.getByText(/Range covers 365 days; pick 92 or fewer/).waitFor();
if ((await page.locator("table.calendar-grid").count()) !== 0) {
  fail("an over-long range still rendered a grid");
}
await step("c03-range-refused");

// A backwards range is the guard's other branch.
await page.goto("http://localhost:5173/calendar?from=2026-04-30&to=2026-04-01", {
  waitUntil: "domcontentloaded",
});
await page.getByText(/The from date must not be after the to date/).waitFor();
await step("c04-backwards-range");

console.log(
  errors.length ? `CONSOLE ERRORS:\n${errors.join("\n")}` : "no unexpected console errors"
);
await browser.close();
if (errors.length) process.exit(1);
