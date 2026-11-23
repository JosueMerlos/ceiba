import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { extname, join } from "node:path";
import { expect, test, type Page } from "@playwright/test";
import {
  DON_EFRAIN,
  RAMIRO,
  RECEPTION,
  appointmentCard,
  bookNewCustomer,
  cancelIfPresent,
  nextWorkingDay,
  openAgenda,
  sidePanel,
  uniquePhone,
} from "../tests/agenda-helpers";
import { shot, signIn } from "../tests/helpers";

// UI QA smoke for the agenda: dragging, a browser in another zone, phone width and the load measurement (meaningful only
// against a production build: the dev server ships every module separately). The pilot scenarios need `SEED_DEMO_PASSWORD=<demo password> bin/rails demo:agenda_pilot`, which creates the "Piloto interno" organization.
const PILOT_RECEPTION = "recepcion@piloto-interno.ceiba.test";
const PILOT_PROFESSIONAL = "profesional@piloto-interno.ceiba.test";
const LOAD_RUNS = 5;
const LOAD_BUDGET_MS = 1500;
const CPU_SLOWDOWN = 4;
const MIN_CARDS = 40;

/** Today in the branch, or the Saturday before when today is a Sunday: the pilot has no appointments on Sundays. */
function pilotDay() {
  const day = new Date(
    `${new Date().toLocaleDateString("en-CA", { timeZone: "America/Managua" })}T12:00:00Z`,
  );
  if (day.getUTCDay() === 0) day.setUTCDate(day.getUTCDate() - 1);
  return day.toISOString().slice(0, 10);
}

const CONTENT_TYPES: Record<string, string> = {
  ".js": "text/javascript",
  ".css": "text/css",
  ".html": "text/html",
  ".woff2": "font/woff2",
  ".svg": "image/svg+xml",
};

/** Serves the panel from a production build (PANEL_DIST) while the API stays the real one, behind the real proxy. */
async function servePanelBuild(page: Page, dist: string) {
  await page.route(
    (url) => !url.pathname.startsWith("/api/"),
    (route) => {
      const { pathname } = new URL(route.request().url());
      const asset = join(dist, pathname);
      const file = existsSync(asset) && statSync(asset).isFile() ? asset : join(dist, "index.html");
      return route.fulfill({
        body: readFileSync(file),
        contentType: CONTENT_TYPES[extname(file)] ?? "application/octet-stream",
      });
    },
  );
}

function watch(page: Page) {
  const problems: string[] = [];
  let anonymousProbes = 0;
  page.on("console", (message) => {
    if (message.type() !== "error") return;
    if (/status of 401/.test(message.text()) && anonymousProbes-- > 0) return;
    problems.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => problems.push(`pageerror: ${error.message}`));
  page.on("response", (response) => {
    if (response.status() === 401 && response.url().endsWith("/api/v1/auth/session")) {
      anonymousProbes += 1;
    } else if (response.status() >= 400) {
      problems.push(`http ${response.status()}: ${response.url()}`);
    }
  });
  return problems;
}

async function openPilot(page: Page, email: string) {
  await signIn(page, email);
  await expect(page.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
  await page.goto(`/agenda?date=${pilotDay()}`);
  await expect(page.locator(".agenda-card").first()).toBeVisible();
}

test.describe("smoke de la agenda", () => {
  test("arrastrar una cita a otro profesional y otra hora la reprograma", async ({
    page,
  }, testInfo) => {
    const problems = watch(page);
    const stamp = Date.now();
    const customer = `smoke-arrastre-${stamp}`;
    const day = nextWorkingDay();
    await openAgenda(page, RECEPTION, day);

    try {
      await bookNewCustomer(page, {
        professional: DON_EFRAIN,
        service: "Corte clásico",
        customer,
        phone: uniquePhone(stamp),
      });
      await page.keyboard.press("Escape");
      const card = appointmentCard(page, customer);
      await card.scrollIntoViewIfNeeded();
      const from = (await card.boundingBox())!;
      const column = (await page.getByRole("group", { name: RAMIRO }).boundingBox())!;

      const moved = page.waitForResponse(
        (response) =>
          response.url().endsWith("/reschedule") && response.request().method() === "POST",
      );
      await page.mouse.move(from.x + from.width / 2, from.y + 8);
      await page.mouse.down();
      await page.mouse.move(from.x + from.width / 2 + 12, from.y + 20, { steps: 4 });
      await page.mouse.move(column.x + column.width / 2, from.y + 8 + 64, { steps: 10 });
      await page.mouse.up();

      const response = await moved;
      expect(response.status()).toBe(201);
      await expect(page.getByText("Cita movida. Queda por confirmar.")).toBeVisible();
      const after = (await appointmentCard(page, customer).boundingBox())!;
      expect(after.x).toBeGreaterThan(from.x + from.width / 2);
      expect(after.y).toBeGreaterThan(from.y);
      await shot(page, testInfo, "30-agenda-arrastre");
    } finally {
      await cancelIfPresent(page, customer);
    }
    expect(problems).toEqual([]);
  });

  test("Nueva cita toma el profesional de la columna clicada, y en la semana el de esa semana", async ({
    page,
  }, testInfo) => {
    const problems = watch(page);
    await openAgenda(page, RECEPTION, nextWorkingDay());
    const professionalOf = async () =>
      (await sidePanel(page, "Nueva cita")
        .getByRole("combobox", { name: "Profesional" })
        .textContent()) ?? "";

    // Two clicks at the same height, so the same hour, in two different columns.
    const below = async (column: string) => {
      const box = (await page.getByRole("group", { name: column }).boundingBox())!;
      return { x: box.x + box.width / 2, y: box.y + box.height + 160 };
    };
    const ramiro = await below(RAMIRO);
    await page.mouse.click(ramiro.x, ramiro.y);
    expect(await professionalOf()).toContain(RAMIRO);
    const efrain = await below(DON_EFRAIN);
    await page.mouse.click(efrain.x, efrain.y);
    expect(await professionalOf()).toContain(DON_EFRAIN);
    await shot(page, testInfo, "34-agenda-columna-clicada");

    await page.keyboard.press("Escape");
    await page.getByRole("button", { name: "Semana", exact: true }).click();
    await page.getByRole("combobox", { name: "Profesional de la semana" }).click();
    await page.getByRole("option", { name: RAMIRO }).click();
    await expect(page.getByRole("heading", { level: 1, name: /semana del/ })).toBeVisible();
    const grid = (await page.locator("[data-slot=agenda-view]").boundingBox())!;
    // Below the day headers, in the middle of the week.
    await page.mouse.click(grid.x + grid.width * 0.5, grid.y + 200);
    expect(await professionalOf()).toContain(RAMIRO);
    await shot(page, testInfo, "35-agenda-semana-nueva-cita");
    expect(problems).toEqual([]);
  });

  test.describe("con el navegador en Madrid", () => {
    test.use({ timezoneId: "Europe/Madrid" });

    test("las citas se ven en la hora de Managua y el día queda completo", async ({
      page,
    }, testInfo) => {
      const problems = watch(page);
      const listing = page.waitForResponse(
        (response) => /\/appointments\?from=/.test(response.url()) && response.ok(),
      );
      await openPilot(page, PILOT_RECEPTION);
      const { data } = (await (await listing).json()) as {
        data: { starts_at: string; status: string; customer_name: string }[];
      };
      const first = data.find((item) => !["cancelled", "rescheduled"].includes(item.status))!;
      const hour = new Intl.DateTimeFormat("es-NI", {
        hour: "numeric",
        minute: "2-digit",
        hour12: true,
        timeZone: "America/Managua",
      })
        .formatToParts(new Date(first.starts_at))
        .filter((part) => part.type === "hour" || part.type === "minute")
        .map((part) => part.value)
        .join(":");

      await expect(appointmentCard(page, first.customer_name).first()).toContainText(hour);
      expect(await page.locator(".agenda-column").count()).toBe(5);
      await shot(page, testInfo, "31-agenda-dia-madrid");
      expect(problems).toEqual([]);
    });
  });

  test("a 360 px la página no se desborda y la grilla se desplaza por dentro", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 360, height: 780 });
    await openPilot(page, PILOT_RECEPTION);
    const widths = await page.evaluate(() => [
      document.documentElement.scrollWidth,
      window.innerWidth,
    ]);
    expect(widths[0]).toBeLessThanOrEqual(widths[1]!);
    await shot(page, testInfo, "32-agenda-360");
  });

  test("el profesional del piloto solo ve su columna", async ({ page }, testInfo) => {
    await openPilot(page, PILOT_PROFESSIONAL);
    await expect(page.locator(".agenda-column")).toHaveCount(1);
    await expect(page.getByRole("button", { name: "Nueva cita" })).toHaveCount(0);
    await shot(page, testInfo, "33-agenda-profesional");
  });

  test("con 40 citas y 5 profesionales queda interactiva en menos de 1.5 s", async ({
    page,
  }, testInfo) => {
    test.setTimeout(120_000);
    const dist = process.env.PANEL_DIST;
    test.skip(!dist, "Needs PANEL_DIST: the dev server is not representative of load time.");
    await servePanelBuild(page, dist!);
    await openPilot(page, PILOT_RECEPTION);
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Emulation.setCPUThrottlingRate", { rate: CPU_SLOWDOWN });

    const runs: number[] = [];
    for (let run = 0; run < LOAD_RUNS; run += 1) {
      await page.goto(`/agenda?date=${pilotDay()}`);
      await expect
        .poll(() => page.locator(".agenda-card").count(), { intervals: [20] })
        .toBeGreaterThanOrEqual(MIN_CARDS);
      // Interactive means an appointment answers a click: the time runs until its panel is on screen.
      await page
        .locator(".ec-event", { has: page.locator(".agenda-card") })
        .first()
        .click();
      await page.locator("[data-slot=context-panel] dl").waitFor();
      runs.push(await page.evaluate(() => Math.round(performance.now())));
    }
    await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });

    const sorted = [...runs].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)]!;
    const report = {
      cpuSlowdown: CPU_SLOWDOWN,
      runsMs: runs,
      medianMs: median,
      budgetMs: LOAD_BUDGET_MS,
    };
    console.warn(`AC5 ${JSON.stringify(report)}`);
    mkdirSync(testInfo.outputDir, { recursive: true });
    writeFileSync(join(testInfo.outputDir, "ac5-load.json"), JSON.stringify(report, null, 2));
    expect(median).toBeLessThan(LOAD_BUDGET_MS);
  });
});
