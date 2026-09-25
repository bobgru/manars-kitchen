/**
 * Demo: compromises — legal assignments that ignore a stated preference.
 *
 * Fixture: `demo/current-period.txt`, the same staffed week as the
 * current-period demo. Run it through the launcher:
 *
 *     web/demos/run.sh compromise            # press Enter to advance
 *     web/demos/run.sh compromise --auto     # timed, e.g. for --record
 *
 * The story: nothing here is broken. Someone did not get what they asked for,
 * and the view says who, where, and why — and lets you hide all of it to see the
 * hard problems alone. ADR 0006 is where the three kinds were settled.
 */
import {
  launch,
  login,
  step,
  finish,
  terminal,
  reveal,
  horizons,
  api,
  terminalCollapsed,
} from "./lib.mjs";

const { browser, context, page } = await launch("Compromise: legal, but not what they wanted");
await login(page);
const { current } = await horizons(page);

// Work out who gives ground most, and on which station, so the captions can
// name them whatever the scheduler chose this time.
const probs = (await api(page, `/api/problems?from=${current.from}&to=${current.to}`)).body;
const workers = (await api(page, "/api/workers?status=all")).body;
const stations = (await api(page, "/api/stations")).body;
const nameOf = (list, id) => list.find((x) => x.id === id)?.name ?? `#${id}`;
const compromises = probs.filter((p) => p.kind === "compromise");
const byWorker = new Map();
for (const p of compromises) byWorker.set(p.worker, (byWorker.get(p.worker) ?? 0) + 1);
const [heavyId, heavyCount] = [...byWorker.entries()].sort((a, b) => b[1] - a[1])[0] ?? [];
const heavy = nameOf(workers, heavyId);
const notPreferred = compromises.filter(
  (p) => p.worker === heavyId && p.compromise.kind === "station-not-preferred"
);
const byStation = new Map();
for (const p of notPreferred) byStation.set(p.station, (byStation.get(p.station) ?? 0) + 1);
const [offStationId] = [...byStation.entries()].sort((a, b) => b[1] - a[1])[0] ?? [];
const offStation = nameOf(stations, offStationId);
const currentPrefs = notPreferred[0]?.compromise.prefs.map((s) => nameOf(stations, s)) ?? [];
const kinds = new Map();
for (const p of compromises) kinds.set(p.compromise.kind, (kinds.get(p.compromise.kind) ?? 0) + 1);
const hard = probs.length - compromises.length;

await step(
  page,
  `This week holds ${probs.length} problems. Only ${hard} of them break a rule.`,
  async () => {
    await terminalCollapsed(page, true);
    await page.locator(".horizon-seg").filter({ hasText: current.label }).click();
    await reveal(page.locator(".horizon-bar"));
  },
  `The other ${compromises.length} are compromises: legal assignments that ignore ` +
    `something a worker asked for. They count, because they are problems by the glossary, ` +
    `but they are a different kind of problem.`
);

await step(
  page,
  "Untick 'Show compromises' and only the hard problems remain.",
  async () => {
    await page.getByRole("checkbox", { name: /Show compromises/ }).uncheck();
    await reveal(page.locator(".horizon-bar"));
  },
  "The counts, the panels and the detail pane all drop them at once. The choice is " +
    "remembered, so a manager who only wants rule breaches sees only rule breaches."
);

await step(
  page,
  "Tick it again. Three kinds of compromise exist, and each has a sentence.",
  async () => {
    await page.getByRole("checkbox", { name: /Show compromises/ }).check();
    await reveal(page.locator('tbody[data-panel="hour"] .problem-cell-compromise').first());
  },
  [...kinds.entries()]
    .map(([k, n]) => `${n} ${k.replace(/-/g, " ")}`)
    .join(", ") +
    ". Authorised overtime is hours past a cap that the worker's terms permit; station not " +
    "preferred is a station outside a worker's list; a variety repeat puts a worker who likes " +
    "to rotate back on a station they just held."
);

await step(
  page,
  "A ~ cell is one where nothing is broken. Click it to read what was given up.",
  async () => {
    await page.locator('tbody[data-panel="hour"] .problem-cell-compromise').first().click();
    await page.getByRole("heading", { name: /problem\(s\)/ }).waitFor();
    await reveal(page.locator(".detail-section").last());
  },
  "A cell shows its most severe kind. A ~ cell is all compromise; a ! cell may hold " +
    "compromises too, and lists them under its violations."
);

await step(
  page,
  "Pick one and its cells are outlined across the panels, named in words below the list.",
  async () => {
    await page.locator(".problem-item").first().click();
    await page.getByText(/^Showing: /).waitFor();
  }
);

await step(
  page,
  `Who gives ground most? ${heavy}, ${heavyCount} times this week.`,
  async () => {
    await reveal(page.locator('tbody[data-panel="worker"] .problem-group'));
  },
  "The worker panel answers that at a glance: the row with the most marks. The " +
    "scheduler honours preferences when it can; a row full of ~ means it mostly could not."
);

await step(
  page,
  `${heavy} prefers ${currentPrefs.join(", ") || "nothing in particular"} and keeps landing on ${offStation}.`,
  async () => {
    await terminalCollapsed(page, false);
    await reveal(page.locator(".terminal"));
  },
  "Two ways out: change the schedule, or change the preference. If " +
    `${heavy} is actually fine with ${offStation}, say so.`
);

const before = compromises.length;
await step(
  page,
  `Add ${offStation} to ${heavy}'s preferences, in the terminal. Watch the count fall.`,
  async () => {
    if (offStationId !== undefined) {
      await terminal(page, `worker set-prefs ${heavy} ${[...currentPrefs, offStation].join(" ")}`);
      // Read the segment's own count element: the label ends in digits, and
      // the two run together in textContent.
      await page.waitForFunction(
        ([label, n]) => {
          const seg = [...document.querySelectorAll(".horizon-seg")].find((s) =>
            s.textContent.includes(label)
          );
          const m = seg?.querySelector(".horizon-count")?.textContent.match(/^(\d+) problem/);
          return m && Number(m[1]) < n;
        },
        [current.label, before + hard],
        { timeout: 30000 }
      );
    }
    await reveal(page.locator(".horizon-bar"));
  },
  "A worker change is not a calendar change, and the page still hears it: every " +
    "topic that can change the answer is watched. The compromises on that station are gone " +
    "because they are no longer compromises — nothing was rescheduled."
);

await step(
  page,
  "What is left is what still needs a decision: real breaches, and preferences nobody has agreed to drop.",
  async () => {
    await terminalCollapsed(page, true);
    await reveal(page.locator('tbody[data-panel="worker"] .problem-group'));
  },
  "Severity decides only what a cell announces. Every problem is still listed when " +
    "you open the cell, so nothing is hidden by ranking — only by your own choice."
);

await finish(page, context, browser, "End of demo: compromises.");
