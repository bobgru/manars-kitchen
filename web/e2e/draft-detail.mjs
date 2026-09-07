/**
 * Drives /drafts/:id in headless Chromium: the empty draft, the populated grid,
 * flagged violations, the replaced-calendar warning, committing from the page
 * itself, and the terminal state for a draft that does not exist.
 *
 * This exists because `tsc` cannot tell you a page works, and because the older
 * `drafts-page.mjs` runs against an empty database — every grid it has ever
 * rendered had zero assignments in it.
 *
 * Prerequisites, none of which this script manages:
 *
 *   1. A database seeded with the demo, which is the only fixture that produces
 *      workers, stations, skills and a calendar to schedule against:
 *
 *        stack exec manars-cli -- --demo demo/restaurant-setup.txt --no-delay
 *        sqlite3 demo-db/demo.db "PRAGMA wal_checkpoint(TRUNCATE);"
 *        rm -f /tmp/mk-detail.db /tmp/mk-detail.db-wal /tmp/mk-detail.db-shm
 *        cp demo-db/demo.db /tmp/mk-detail.db
 *
 *      **Checkpoint before copying.** The demo leaves most of what it wrote in
 *      `demo-db/demo.db-wal`, so copying the `.db` alone yields a database with
 *      zero calendar rows and every assertion below fails for a reason that has
 *      nothing to do with the page.
 *
 *      The demo ends with *zero* drafts — every one it makes is committed or
 *      discarded — so this script creates its own. Draft ids continue from the
 *      demo's, so nothing here assumes #1; ids are read off the page.
 *
 *      This script mutates that database (two drafts, a capped worker, two
 *      commits), so re-run it against a fresh copy, not a used one.
 *   2. `stack exec manars-server -- /tmp/mk-detail.db` on port 8080.
 *   3. `npm run dev` in web/ on port 5173, which proxies /api to 8080.
 *   4. `npx playwright install chromium` once.
 *
 * Screenshots land in web/e2e/screenshots/, which is gitignored. Look at them: a
 * blank frame means the app never rendered, and every assertion below would
 * still have to fail for you to notice otherwise.
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

/**
 * A screenshot of one element.
 *
 * Needed because the app shell scrolls its content pane internally, so
 * `fullPage` stops at the terminal and everything below the fold -- the whole
 * violations table, for one -- is missing from a full-page capture.
 */
const shotOf = async (locator, name) => {
  await locator.screenshot({ path: `${SHOTS}${name}.png` });
  console.log(`--- ${name}`);
};

const sectionFor = (heading) =>
  page.locator(".detail-section").filter({ has: page.getByRole("heading", { name: heading }) });

/** A date `days` from today, as YYYY-MM-DD. */
const iso = (days) => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};

/**
 * Call the API as the logged-in admin, from inside the page so the bearer token
 * in sessionStorage is reachable.
 *
 * Used only to manufacture server state the admin UI cannot create -- there is no
 * REST route for a worker's hour limit anywhere in the pages under test, and a
 * violation has to come from somewhere.
 */
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

const fail = (msg) => {
  errors.push(`ASSERTION: ${msg}`);
  console.log(`ASSERTION FAILED: ${msg}`);
};

const FROM = iso(30);
const TO = iso(36);

// --- Log in ----------------------------------------------------------------
await page.goto("http://localhost:5173/", { waitUntil: "domcontentloaded" });
await page.getByLabel("Username").fill("admin");
await page.getByLabel("Password").fill("admin");
await page.getByRole("button", { name: /log ?in/i }).click();
await page.getByRole("link", { name: "Drafts", exact: true }).waitFor();
console.log("logged in");

// --- Create draft A, then follow the link the list page now carries ---------
await page.getByRole("link", { name: "Drafts", exact: true }).click();
await page.getByRole("heading", { name: "Drafts" }).waitFor();
await page.getByRole("button", { name: "New Draft" }).click();
await page.locator('input[type="date"]').first().fill(FROM);
await page.locator('input[type="date"]').nth(1).fill(TO);
await page.getByRole("button", { name: "Create", exact: true }).click();

const toast = await page.getByText(/Created draft #\d+\./).textContent();
const idA = toast.match(/#(\d+)/)[1];
console.log(`draft A is #${idA}`);

await page.getByRole("link", { name: `#${idA}`, exact: true }).click();
await page.getByRole("heading", { name: `Draft #${idA}` }).waitFor();
// Not empty, even before Generate: pins seed every draft, and the demo pins
// Marco to grill on Monday mornings. A draft over a week the calendar knows
// nothing about still opens with whatever the pins put in it.
await page.locator("table.calendar-grid").waitFor();
const seeded = await page.locator(".calendar-chip").count();
console.log(`seeded from pins: ${seeded} chips`);
await step("d01-seeded-draft");

// --- Generate, from the detail page ----------------------------------------
await page.getByRole("button", { name: "Generate" }).click();
await page.getByText(/Generated \d+ assignment\(s\)/).waitFor();
await page.locator("table.calendar-grid").waitFor();
const chips = await page.locator(".calendar-chip").count();
if (chips === 0) fail("generated draft rendered no chips in the grid");
console.log(`grid shows ${chips} chips`);

// A freshly generated draft is clean on this fixture as of 2026-09-07, when the
// scheduler and the validator stopped disagreeing about authorised overtime.
// This still asserts a *delta* rather than "before is 0", because whether a
// generated schedule happens to be clean depends on the fixture, and that is not
// what these steps are testing.
const violationsHeading = () => page.getByRole("heading", { name: /^Violations \(/ });
const violationCount = async () =>
  Number((await violationsHeading().textContent()).match(/\((\d+)\)/)[1]);
await violationsHeading().waitFor();
const before = await violationCount();
console.log(`violations straight after generate: ${before}`);
await step("d02-generated-grid");

// --- Manufacture a violation ------------------------------------------------
// Cap the hours of the worker the draft leans on hardest, so their assignments
// break the period-hours rule. Picking by assignment count rather than by name
// keeps this independent of what the scheduler chose, and picking the *busiest*
// avoids a worker who is already violating -- the demo's admin has seven
// assignments and all seven already fail, so capping them changes nothing.
const assigned = await api(`/api/drafts/${idA}/assignments`);
const perWorker = new Map();
for (const a of assigned.body.assignments) {
  perWorker.set(a.worker, (perWorker.get(a.worker) ?? 0) + 1);
}
const [workerId, count] = [...perWorker.entries()].sort((x, y) => y[1] - x[1])[0] ?? [];
if (workerId === undefined) fail("draft reported no assignments over REST");
const workers = await api("/api/workers?status=all");
const victim = workers.body.find((w) => w.id === workerId);
console.log(`capping hours for ${victim.name} (worker ${workerId}, ${count} assignments)`);
const capped = await api(`/api/workers/${encodeURIComponent(victim.name)}/hours`, {
  method: "PUT",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ hours: 1 }),
});
if (capped.status !== 204 && capped.status !== 200) {
  fail(`capping hours returned ${capped.status}`);
}

// A worker mutation is not a draft or calendar event, so the page does not
// reload itself. That is deliberate -- see the SSE subscriptions.
await page.reload({ waitUntil: "domcontentloaded" });
await page.getByRole("heading", { name: `Draft #${idA}` }).waitFor();
await violationsHeading().waitFor();
const after = await violationCount();
if (after <= before) {
  fail(`capping ${victim.name}'s hours added no violations (${before} -> ${after})`);
}
const flagged = await page.locator(".calendar-chip-flagged").count();
if (flagged === 0) fail("violations reported but no chip was flagged in the grid");
await page.getByText(/still in the draft/).waitFor();
// The capped worker has to be named in the table, not just counted.
await page.getByRole("cell", { name: victim.name, exact: true }).first().waitFor();
await page.getByRole("cell", { name: "period hours" }).first().waitFor();
console.log(`violations now ${after}, ${flagged} chips flagged`);
await step("d03-violations");
await shotOf(sectionFor(/^Violations \(/), "d03b-violations-table");
// The flagged chip's own treatment: a "!", bold weight, a thicker border and a
// yellow on the blue-yellow axis -- so it survives being read in greyscale.
await shotOf(page.locator(".calendar-chip-flagged").first(), "d03c-flagged-chip");

// --- Move the baseline underneath it ---------------------------------------
// A sibling draft over the same dates, committed, is exactly ADR 0003's trap.
await page.getByRole("link", { name: "Drafts", exact: true }).click();
await page.getByRole("button", { name: "New Draft" }).click();
await page.locator('input[type="date"]').first().fill(FROM);
await page.locator('input[type="date"]').nth(1).fill(TO);
await page.getByRole("button", { name: "Create", exact: true }).click();
const toastB = await page.getByText(/Created draft #\d+\./).textContent();
const idB = toastB.match(/#(\d+)/)[1];
console.log(`draft B is #${idB}`);

await page
  .getByRole("row", { name: new RegExp(`#${idB}`) })
  .getByRole("button", { name: "Generate" })
  .click();
await page.getByText(new RegExp(`Generated draft #${idB}`)).waitFor();

await page
  .getByRole("row", { name: new RegExp(`#${idB}`) })
  .getByRole("button", { name: "Commit" })
  .click();
await page.getByRole("heading", { name: new RegExp(`Commit draft #${idB}`) }).waitFor();
await page.getByPlaceholder(/What this commit is for/).fill("sibling over A's week");
await page.getByRole("button", { name: "Commit", exact: true }).last().click();
// The shared dialog's second step, reached from the list page.
await page.getByRole("heading", { name: /Other drafts cover these dates/ }).waitFor();
await page.getByRole("button", { name: "Commit Anyway" }).click();
await page.getByText(/replacing the overlapping dates/).waitFor();
await step("d04-sibling-committed");

await page.getByRole("link", { name: `#${idA}`, exact: true }).click();
await page.getByRole("heading", { name: `Draft #${idA}` }).waitFor();
await page.getByText(/the calendar under these dates was replaced by/).waitFor();
await page.getByRole("link", { name: /See what the calendar holds now/ }).waitFor();
await step("d05-replaced-warning");

// --- Commit from the detail page -------------------------------------------
// The draft is deleted by this, so the page has to navigate and hand its
// confirmation to the list.
await page.getByRole("button", { name: "Commit" }).click();
await page.getByRole("heading", { name: new RegExp(`Commit draft #${idA}`) }).waitFor();
await page.getByPlaceholder(/What this commit is for/).fill("from the detail page");
await page.getByRole("button", { name: "Commit", exact: true }).last().click();
await page.getByRole("heading", { name: "Drafts" }).waitFor();
await page.getByText(new RegExp(`Committed draft #${idA} to the calendar`)).waitFor();
if (!page.url().endsWith("/drafts")) fail(`expected to land on /drafts, got ${page.url()}`);
await step("d06-committed-handoff");

// --- A draft that is not there ---------------------------------------------
await page.goto("http://localhost:5173/drafts/999999", {
  waitUntil: "domcontentloaded",
});
await page.getByText(/does not exist. It may have been committed or discarded/).waitFor();
await step("d07-gone");

// The overlapping commit is a deliberate 409, which Chromium logs as a failed
// resource load; so is the 404 behind the terminal state above. Both are handled
// in the UI. Anything else here is not expected.
const unexpected = errors.filter(
  (e) => !/409 \(Conflict\)/.test(e) && !/404 \(Not Found\)/.test(e)
);
console.log(
  unexpected.length
    ? `CONSOLE ERRORS:\n${unexpected.join("\n")}`
    : "no unexpected console errors"
);
await browser.close();
if (unexpected.length) process.exit(1);
