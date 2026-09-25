/**
 * Demo: a tour of the admin pages.
 *
 * Fixture: `demo/restaurant-setup.txt` — the CLI feature tour, pinned to a fixed
 * historical week (April 2026) because its freeze-line section needs dates in the
 * past. Run it through the launcher:
 *
 *     web/demos/run.sh feature-tour            # press Enter to advance
 *     web/demos/run.sh feature-tour --auto     # timed, e.g. for --record
 *
 * The story: the reference data — skills, stations and their zones, workers,
 * shifts — then how a schedule is built (drafts), where it lands (the calendar),
 * and the one rule that protects the past (the freeze line). It ends where the
 * app opens, the problem view, and says why that view is empty for this fixture.
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
} from "./lib.mjs";

const { browser, context, page } = await launch("Feature tour: the admin pages");
await login(page);
const { next } = await horizons(page);

await step(
  page,
  "The app opens on the problem view. This fixture's calendar is April 2026, so every day in range is 'not scheduled'.",
  null,
  "The problem view scopes to today, this pay period and the next. Nothing here is " +
    "wrong with the restaurant; nothing has been built for these dates yet, and the view " +
    "says so once per day rather than once per open station-slot."
);

await step(
  page,
  "Skills: what workers hold and stations require. One skill can imply others.",
  async () => {
    await navigate(page, "Skills");
    await reveal(page.locator("table.data-table"));
  },
  "master-chef implies every line skill, so granting it grants them all."
);

await step(
  page,
  "A skill's page: rename it, and see what it implies.",
  async () => {
    await page.getByRole("link", { name: "master-chef" }).click();
    await page.getByRole("heading", { name: /master-chef/ }).first().waitFor();
  }
);

await step(
  page,
  "Stations: the places that need staffing, each with a zone saying where it is.",
  async () => {
    await navigate(page, "Stations");
    await reveal(page.locator("table.data-table"));
  },
  "Zones are free-text labels — hot line, cold line, front, back. The problem view's " +
    "station panel groups by them. busboy has none and shows as Unassigned."
);

await step(
  page,
  "A station's page: its name, its zone, and its staffing minimum and maximum.",
  async () => {
    await page.getByRole("link", { name: "grill" }).click();
    await page.getByRole("heading", { name: "Station: grill" }).waitFor();
    await reveal(page.getByRole("heading", { name: "Zone" }));
  },
  "Hours, closures and required skills are set from the CLI; the terminal below is " +
    "that CLI."
);

await step(
  page,
  "Workers: everyone who can be assigned, with status, seniority and whether they are temps.",
  async () => {
    await navigate(page, "Workers");
    await reveal(page.locator("table.data-table"));
  },
  "A worker is a user account with a worker profile; the two share an identity."
);

await step(
  page,
  "A worker's page: skills, hour limits, overtime model, station and shift preferences, pairing.",
  async () => {
    await page.getByRole("link", { name: "marco" }).click();
    await page.getByRole("heading", { name: /marco/ }).first().waitFor();
    await reveal(page.getByRole("heading", { name: /Employment/ }));
  },
  "Most of this is read-only here and edited through the CLI; the page says so section " +
    "by section."
);

await step(
  page,
  "Shifts: named hour ranges the scheduler groups slots into.",
  async () => {
    await navigate(page, "Shifts");
    await reveal(page.locator("table.data-table"));
  },
  "morning, midday, lunch-rush, afternoon, evening. Workers can state a shift " +
    "preference, though the scheduler does not yet score it."
);

await step(
  page,
  "Drafts: every schedule is built inside a draft and reaches the calendar by committing it.",
  async () => {
    await navigate(page, "Drafts");
  },
  "The tour committed or discarded all of its drafts, so the list is empty. A draft " +
    "is a proposal over a date range: generate it, look at it, then commit it."
);

await step(
  page,
  "The freeze line: yesterday. The past is not to be rewritten, and the page refuses a draft over it.",
  async () => {
    await page.getByRole("button", { name: "New Draft" }).click();
    await page.locator('input[type="date"]').first().fill("2026-04-06");
    await page.locator('input[type="date"]').nth(1).fill("2026-04-12");
    await page.getByRole("button", { name: "Create", exact: true }).click();
    await page.getByRole("heading", { name: /frozen dates/i }).waitFor();
  },
  "Only the CLI can force past it, in the same session, and the modal says exactly how."
);

await step(
  page,
  `A draft over next period (${next.from} to ${next.to}) is fine: nothing there is frozen.`,
  async () => {
    await page.getByRole("button", { name: "Close" }).click();
    // The inline form stays open after a refusal; only reopen it if it closed.
    const newDraft = page.getByRole("button", { name: "New Draft" });
    if (await newDraft.isVisible().catch(() => false)) await newDraft.click();
    await page.locator('input[type="date"]').first().fill(next.from);
    await page.locator('input[type="date"]').nth(1).fill(next.to);
    await page.getByRole("button", { name: "Create", exact: true }).click();
    await page.getByText(/Created draft #\d+\./).waitFor();
  },
  "It exists, and it is empty. Generating fills it from the scheduler."
);

await step(
  page,
  "Generate: the scheduler staffs every open station-slot it can, honouring skills, hours and rules.",
  async () => {
    await page.getByRole("button", { name: "Generate" }).first().click();
    await page.getByText(/Generated draft #\d+/).waitFor();
  },
  "The row reports how many slots were assigned and how many it could not fill."
);

await step(
  page,
  "A draft's page: the schedule as a grid, and every assignment that breaks a rule.",
  async () => {
    await page.locator('a[href^="/drafts/"]').first().click();
    await page.getByRole("heading", { name: /^Draft #\d+/ }).waitFor();
    await reveal(page.getByRole("heading", { name: /^Violations/ }));
  },
  "Violations are reported here, never silently pruned; the admin decides what to do " +
    "about them."
);

await step(
  page,
  "The calendar: what has actually been committed, for any date range.",
  async () => {
    await navigate(page, "Calendar");
    await page.locator('input[type="date"]').first().fill("2026-04-06");
    await page.locator('input[type="date"]').nth(1).fill("2026-04-12");
    await page.locator("table.calendar-grid").waitFor();
    await reveal(page.locator("table.calendar-grid"));
  },
  "The first week of the tour. Hours down the side, days across, a chip per assignment."
);

await step(
  page,
  "The terminal is the full CLI. Ask it about the freeze line, and list the drafts.",
  async () => {
    await reveal(page.locator(".terminal"));
    await terminal(page, "calendar freeze-status");
    await terminal(page, "draft list");
  },
  "Whatever the CLI changes, the pages hear about over a live event stream; the " +
    "current-period demo shows that end to end."
);

await step(
  page,
  "Back where we started. For a populated problem view, run the current-period demo.",
  async () => {
    await navigate(page, "Dashboard", "Problems");
  },
  "Its fixture staffs this week and then approves a sick call, which is the case the " +
    "problem view is built around."
);

await finish(page, context, browser, "End of the feature tour.");
