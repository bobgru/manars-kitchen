/**
 * Shared plumbing for the browser demos in this directory.
 *
 * A demo is a plain list of steps. Each step shows a caption — in a banner
 * injected into the page and again in the terminal — runs an action, and then
 * waits: for Enter by default, so a presenter can talk over it for as long as
 * they like, or for a fixed delay under `--auto`, which is what you want when
 * recording or watching unattended.
 *
 * Unlike the drivers in `web/e2e/`, nothing here asserts. A demo that fails
 * loudly mid-sentence is worse than one that keeps going, so actions are
 * wrapped and a failed step is reported in the terminal and skipped.
 *
 * Flags, all optional:
 *   --auto [ms]     advance automatically after ms (default 3500) instead of Enter
 *   --record        save a .webm of the session under demos/recordings/
 *   --headless      no window; for checking a demo still runs
 *   --slow <ms>     slow-motion delay per browser action (default 250 headed, 0 headless)
 *   --shots         save a screenshot per step under demos/screenshots/ (for checking a
 *                   demo without watching it)
 *   --base <url>    the app, default http://localhost:5173
 */
import { chromium } from "playwright";
import { mkdir } from "node:fs/promises";
import { createInterface } from "node:readline";

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const value = (name, fallback) => {
  const i = argv.indexOf(name);
  if (i === -1) return fallback;
  const v = argv[i + 1];
  return v === undefined || v.startsWith("--") ? fallback : v;
};

export const options = {
  auto: flag("--auto") ? Number(value("--auto", "3500")) : null,
  record: flag("--record"),
  headless: flag("--headless"),
  shots: flag("--shots"),
  slow: Number(value("--slow", flag("--headless") ? "0" : "250")),
  base: value("--base", "http://localhost:5173"),
};

const RECORDINGS = new URL("./recordings/", import.meta.url).pathname;
const SCREENSHOTS = new URL("./screenshots/", import.meta.url).pathname;

let stepNumber = 0;
let rl = null;
let demoSlug = "demo";

/** Open the browser and a page. Headed unless --headless; recording if --record. */
export async function launch(name) {
  const browser = await chromium.launch({
    headless: options.headless,
    slowMo: options.slow,
    args: ["--no-sandbox"],
  });
  const contextOptions = { viewport: { width: 1440, height: 900 } };
  if (options.record) {
    await mkdir(RECORDINGS, { recursive: true });
    contextOptions.recordVideo = { dir: RECORDINGS, size: contextOptions.viewport };
  }
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  page.on("pageerror", (e) => console.log(`  [page error] ${e}`));
  demoSlug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  if (options.shots) await mkdir(SCREENSHOTS, { recursive: true });
  console.log(`\n=== ${name}`);
  console.log(
    options.auto === null
      ? "Press Enter to advance each step. Ctrl-C to stop."
      : `Advancing automatically every ${options.auto} ms.`
  );
  return { browser, context, page };
}

/** Log in as the default admin and land on the problem view. */
export async function login(page) {
  await page.goto(options.base + "/", { waitUntil: "domcontentloaded" });
  await page.getByLabel("Username").fill("admin");
  await page.getByLabel("Password").fill("admin");
  await page.getByRole("button", { name: /log ?in/i }).click();
  await page.getByRole("heading", { name: "Problems" }).waitFor();
}

/**
 * Show a caption in a banner across the top of the page. Bright white on a dark
 * band with a white rule, so it reads over any page without relying on hue.
 * The banner is created on first use and survives client-side navigation; a
 * full reload would drop it, which is why demos never reload.
 */
export async function caption(page, text, sub = "") {
  await page.evaluate(
    ([t, s]) => {
      let el = document.getElementById("demo-caption");
      if (!el) {
        el = document.createElement("div");
        el.id = "demo-caption";
        // In normal flow above the app shell, not fixed over it, so the banner
        // never hides the app's own header; the shell is shrunk to fit below.
        // Sticky so that if the document does scroll — smooth scrolling into a
        // grid can move it a little — the banner stays in view.
        Object.assign(el.style, {
          position: "sticky",
          top: "0",
          zIndex: "99999",
          background: "#0b1020",
          color: "#ffffff",
          borderBottom: "3px solid #ffffff",
          padding: "14px 24px",
          font: "600 19px/1.35 system-ui, sans-serif",
          boxShadow: "0 4px 18px rgba(0,0,0,0.6)",
        });
        const main = document.createElement("div");
        main.id = "demo-caption-main";
        const small = document.createElement("div");
        small.id = "demo-caption-sub";
        Object.assign(small.style, {
          font: "400 15px/1.35 system-ui, sans-serif",
          color: "#dddddd",
          marginTop: "4px",
        });
        el.append(main, small);
        document.body.prepend(el);
      }
      el.querySelector("#demo-caption-main").textContent = t;
      const subEl = el.querySelector("#demo-caption-sub");
      subEl.textContent = s;
      subEl.style.display = s ? "block" : "none";
      const shell = document.querySelector(".app-shell");
      if (shell) shell.style.height = `calc(100vh - ${el.offsetHeight}px)`;
    },
    [text, sub]
  );
}

/** Wait for the presenter (Enter) or the clock (--auto). */
export async function pause(ms = options.auto) {
  if (options.auto !== null) {
    await new Promise((r) => setTimeout(r, ms ?? options.auto));
    return;
  }
  if (!rl) {
    rl = createInterface({ input: process.stdin, output: process.stdout });
  }
  await new Promise((resolve) => rl.question("  [Enter] ", () => resolve()));
}

/**
 * One step: caption, action, pause. The caption goes up before the action so
 * the viewer knows what they are about to see, and stays while they look.
 */
export async function step(page, text, action, sub = "") {
  stepNumber += 1;
  console.log(`\n${stepNumber}. ${text}`);
  if (sub) console.log(`   ${sub}`);
  await caption(page, text, sub);
  try {
    if (action) await action();
  } catch (err) {
    console.log(`   [step failed, continuing] ${err.message ?? err}`);
    await caption(page, text, `(this step did not complete: ${err.message ?? err})`);
  }
  if (options.shots) {
    const file = `${SCREENSHOTS}${demoSlug}-${String(stepNumber).padStart(2, "0")}.png`;
    await page.screenshot({ path: file });
  }
  await pause();
}

/** Type a command into the embedded web terminal and wait for its output. */
export async function terminal(page, command) {
  const input = page.locator(".terminal-input");
  const before = await page.locator(".terminal-line").count();
  await input.click();
  await input.pressSequentially(command, { delay: options.headless ? 0 : 45 });
  await input.press("Enter");
  await page.waitForFunction(
    (n) => document.querySelectorAll(".terminal-line").length > n + 1,
    before,
    { timeout: 20000 }
  );
}

/** Call the API as the logged-in admin, from inside the page. */
export function api(page, path, init) {
  return page.evaluate(
    async ([p, i]) => {
      const token = sessionStorage.getItem("token");
      const resp = await fetch(p, {
        ...i,
        headers: { ...(i?.headers ?? {}), Authorization: `Bearer ${token}` },
      });
      const text = await resp.text();
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
}

/** Scroll an element into the middle of the viewport, gently. */
export async function reveal(locator) {
  await locator.first().evaluate((el) =>
    el.scrollIntoView({ block: "center", behavior: "smooth" })
  );
}

/** Go to a page through the sidebar, like a person would. */
export async function navigate(page, label, headingName = label) {
  await page.getByRole("link", { name: label, exact: true }).click();
  await page.getByRole("heading", { name: headingName }).first().waitFor();
}

/** Closing caption, final pause, then shut down and report any recording. */
export async function finish(page, context, browser, text = "End of demo.") {
  await caption(page, text, "Close this window or press Enter in the terminal.");
  console.log(`\n${text}`);
  await pause();
  const video = options.record ? page.video() : null;
  await context.close();
  if (video) console.log(`Recording saved: ${await video.path()}`);
  await browser.close();
  rl?.close();
}

/** Today and the horizon ranges as the server sees them. */
export async function horizons(page) {
  const { body } = await api(page, "/api/horizons");
  const by = Object.fromEntries(body.map((h) => [h.key, h]));
  return { today: by.today.from, current: by["current-period"], next: by["next-period"] };
}

/** ISO date n days from an ISO date. */
export function plusDays(iso, n) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(y, m - 1, d + n);
  const p = (x) => String(x).padStart(2, "0");
  return `${dt.getFullYear()}-${p(dt.getMonth() + 1)}-${p(dt.getDate())}`;
}
