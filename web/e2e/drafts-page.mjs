/**
 * Drives the /drafts page in headless Chromium: create (including the frozen
 * refusal), generate, commit, the overlapping-drafts 409 and its force
 * override, and discard.
 *
 * This exists because `tsc` cannot tell you a page works. Two of the older
 * pages were type-checked and reasoned about but never exercised, and
 * docs/STATUS.md has carried that caveat ever since.
 *
 * Prerequisites, none of which this script manages:
 *
 *   1. A *fresh* database. It asserts on draft ids starting at #1 and on the
 *      empty-list state, so a database with drafts already in it fails at the
 *      first step.
 *   2. `stack exec manars-server -- <that db>` on port 8080.
 *   3. `npm run dev` in web/ on port 5173, which proxies /api to 8080.
 *   4. `npx playwright install chromium` once.
 *
 * Screenshots land in web/e2e/screenshots/, which is gitignored. Look at them:
 * a blank frame means the app never rendered, and every assertion below would
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

/** A date `days` from today, as YYYY-MM-DD. */
const iso = (days) => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};

await page.goto("http://localhost:5173/", { waitUntil: "domcontentloaded" });
await page.getByLabel("Username").fill("admin");
await page.getByLabel("Password").fill("admin");
await page.getByRole("button", { name: /log ?in/i }).click();
await page.getByRole("link", { name: "Drafts" }).waitFor();
console.log("logged in");

await page.getByRole("link", { name: "Drafts" }).click();
await page.getByRole("heading", { name: "Drafts" }).waitFor();
await page.getByText(/No drafts/).waitFor();
await step("01-empty");

// --- Create ---------------------------------------------------------------
// A past range is refused by the freeze line, and REST offers no override, so
// the modal has to point at the CLI rather than at a force button.
await page.getByRole("button", { name: "New Draft" }).click();
await page.locator('input[type="date"]').first().fill("2026-04-06");
await page.locator('input[type="date"]').nth(1).fill("2026-04-12");
await page.getByRole("button", { name: "Create", exact: true }).click();
await page.getByRole("heading", { name: /frozen dates/i }).waitFor();
await step("02-frozen-refusal");
await page.getByRole("button", { name: "Close" }).click();

// Caught client-side: no request goes out for a backwards range.
await page.locator('input[type="date"]').first().fill(iso(36));
await page.locator('input[type="date"]').nth(1).fill(iso(30));
await page.getByRole("button", { name: "Create", exact: true }).click();
await page.getByText(/must not be after/).waitFor();
await step("03-bad-range");

await page.locator('input[type="date"]').first().fill(iso(30));
await page.locator('input[type="date"]').nth(1).fill(iso(36));
await page.getByRole("button", { name: "Create", exact: true }).click();
await page.getByText(/Created draft #1\./).waitFor();
await page.getByRole("cell", { name: "#1", exact: true }).waitFor();
await step("04-created");

// --- Generate --------------------------------------------------------------
await page.getByRole("button", { name: "Generate" }).click();
await page.getByText(/Generated draft #1/).waitFor();
await step("05-generated");

// --- Commit, the 409, and the force override -------------------------------
// A second draft over the same dates is allowed to exist; that is the point of
// ADR 0003. It is the commit that has to object.
await page.getByRole("button", { name: "New Draft" }).click();
await page.locator('input[type="date"]').first().fill(iso(30));
await page.locator('input[type="date"]').nth(1).fill(iso(36));
await page.getByRole("button", { name: "Create", exact: true }).click();
await page.getByText(/Created draft #2\./).waitFor();
await step("06-two-overlapping");

await page.getByRole("row", { name: /#1/ }).getByRole("button", { name: "Commit" }).click();
await page.getByRole("heading", { name: /Commit draft #1/ }).waitFor();
await page.getByPlaceholder(/What this commit is for/).fill("from the page");
await page.getByRole("button", { name: "Commit", exact: true }).last().click();
await page.getByRole("heading", { name: /Other drafts cover these dates/ }).waitFor();
await step("07-commit-conflict");

await page.getByRole("button", { name: "Commit Anyway" }).click();
await page.getByText(/replacing the overlapping dates/).waitFor();
// Draft #2's baseline just moved underneath it, and the row has to say so —
// this is the blind spot ADR 0003 called out.
await page.getByText(/calendar replaced by draft #1/).waitFor();
await step("08-forced-and-warned");

// --- Discard ---------------------------------------------------------------
await page.getByRole("button", { name: "Discard" }).click();
await page.getByRole("heading", { name: /Discard draft #2/ }).waitFor();
await step("09-discard-confirm");
await page.getByRole("button", { name: "Discard", exact: true }).last().click();
await page.getByText(/Discarded draft #2\./).waitFor();
await page.getByText(/No drafts/).waitFor();
await step("10-empty-again");

// The two deliberate 409s (frozen range, overlapping commit) are logged by
// Chromium as failed resource loads. Both are handled into modals above, so
// they are expected; anything else here is not.
const unexpected = errors.filter((e) => !/409 \(Conflict\)/.test(e));
console.log(
  unexpected.length ? `CONSOLE ERRORS:\n${unexpected.join("\n")}` : "no unexpected console errors"
);
await browser.close();
if (unexpected.length) process.exit(1);
