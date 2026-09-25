/**
 * Demo: the problem view over a staffed week, and the sick call.
 *
 * Fixture: `demo/current-period.txt` — the current pay period is staffed and
 * committed, Nina's absence for two of its days was approved *after* the commit,
 * and the next period is deliberately empty. Run it through the launcher, which
 * seeds that fixture and starts everything:
 *
 *     web/demos/run.sh current-period            # press Enter to advance
 *     web/demos/run.sh current-period --auto     # timed, e.g. for --record
 *
 * The story: the calendar did not change, and yet it has problems. That is the
 * case the problem view exists for (ADR 0004).
 */
import {
  launch,
  login,
  step,
  finish,
  terminal,
  reveal,
  navigate,
  horizons,
  plusDays,
  terminalCollapsed,
} from "./lib.mjs";

const { browser, context, page } = await launch("Current period: the sick call");
await login(page);
const { today, current, next } = await horizons(page);
const sickFrom = plusDays(today, 2);
const sickTo = plusDays(today, 3);

await step(
  page,
  "This is the problem view: what is wrong with the committed calendar, right now.",
  async () => {
    await terminalCollapsed(page, true);
  },
  `The horizon control offers today, this pay period (${current.from} to ${current.to}) ` +
    `and the next. Everything below is scoped to the selected one. The terminal is ` +
    `collapsed to its bar at the bottom to give the view the room; it comes back later.`
);

await step(
  page,
  "The current period is fully staffed. So why does it report problems?",
  async () => {
    await page.locator(".horizon-seg").filter({ hasText: current.label }).click();
    await reveal(page.locator(".horizon-bar"));
  },
  "Each segment says how many problems it holds and from when: the answer to " +
    "\"must I act today\", not just a count."
);

await step(
  page,
  `Nina called in sick for ${sickFrom} and ${sickTo}, after the week was committed.`,
  async () => {
    await reveal(page.locator('tbody[data-panel="hour"] .problem-mark').first());
  },
  "Nothing about the calendar changed. Her hours are still on it, and every one of " +
    "them now breaks the absence rule. The view recomputes rather than reading stored " +
    "violations, so it sees this immediately."
);

await step(
  page,
  "Every mark is a glyph plus a count. ! is a violation, ▼ understaffed, ○ not scheduled.",
  null,
  "Colour is only a second cue. The meaning survives on a monochrome screen and for " +
    "anyone who cannot tell the fills apart."
);

await step(
  page,
  "Clicking a cell lists what is wrong in that hour, in words.",
  async () => {
    await page.locator('tbody[data-panel="hour"] .problem-mark').first().click();
    await page.getByRole("heading", { name: /problem\(s\)/ }).waitFor();
    await reveal(page.locator(".detail-section").last());
  }
);

await step(
  page,
  "Picking one problem outlines its hour, its worker and its station across all three panels.",
  async () => {
    await page.locator(".problem-item").first().click();
    await page.getByText(/^Showing: /).waitFor();
    await reveal(page.locator('tbody[data-panel="worker"]'));
  },
  "The caption under the list says where it is, so three outlines never have to be " +
    "decoded on their own."
);

await step(
  page,
  "The worker panel: one row per active worker, so an empty row means that person is fine.",
  async () => {
    await reveal(page.locator('tbody[data-panel="worker"] .problem-group'));
  },
  "Nina's row carries the marks. Nobody else's does."
);

await step(
  page,
  "The station panel groups stations by zone, so a hot area reads as a block.",
  async () => {
    await reveal(page.locator('tbody[data-panel="station"] .problem-group'));
  },
  "Zones are labels on stations — hot line, cold line, front, back — and stations " +
    "without one sit under Unassigned. The same dates line up down all three panels."
);

await step(
  page,
  "Next period: nobody has built it yet, and the view says that once, not 600 times.",
  async () => {
    await page.getByRole("button", { name: "Close" }).click();
    await page.locator(".horizon-seg").filter({ hasText: next.label }).click();
    await reveal(page.locator(".horizon-bar"));
  },
  "A day with no assignments at all is one 'not scheduled' problem in its header, " +
    "with hatched cells below. Understaffing presupposes an attempt to staff."
);

await step(
  page,
  "Back to this period. Now a second sick call, live, from the terminal.",
  async () => {
    await page.locator(".horizon-seg").filter({ hasText: current.label }).click();
    await terminalCollapsed(page, false);
    await reveal(page.locator(".terminal"));
  },
  "The embedded terminal is the same CLI an admin uses at a shell. The browser and the " +
    "CLI are one system, and the page listens for what the CLI does."
);

const before = await page.locator(".problem-mark").count();
await step(
  page,
  `Marco is off tomorrow (${plusDays(today, 1)}). Give him an allowance, request it, approve it.`,
  async () => {
    await terminal(page, "absence set-allowance marco sick 10");
    await terminal(page, `absence request sick marco ${plusDays(today, 1)} ${plusDays(today, 1)}`);
    await terminal(page, "absence approve 2");
    await page.waitForFunction(
      (n) => document.querySelectorAll(".problem-mark").length > n,
      before,
      { timeout: 30000 }
    );
    await reveal(page.locator(".horizon-bar"));
  },
  "Watch the counts on the horizon control and the new marks appear without a reload. " +
    "An approved absence changes the answer without touching the calendar."
);

await step(
  page,
  "The calendar itself, for comparison: the assignments are all still there.",
  async () => {
    await navigate(page, "Calendar");
    await page.locator('input[type="date"]').first().fill(current.from);
    await page.locator('input[type="date"]').nth(1).fill(current.to);
    await page.locator("table.calendar-grid").waitFor();
  },
  "This is what was committed. It has not changed. The problems live in the gap " +
    "between it and the rules, which is why they are computed rather than stored."
);

await finish(page, context, browser, "End of demo: the problem view and the sick call.");
