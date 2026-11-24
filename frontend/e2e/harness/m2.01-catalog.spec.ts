import { expect, test, type Page } from "@playwright/test";
import { horizontalOverflow, shot, signIn } from "../tests/helpers";

// UI QA smoke for the catalog panel. It complements tests/catalog.spec.ts (AC1/AC2/AC6) with AC3, AC4, AC5, the shell
// (sidebar, ContextPanel) and a 360 px pass. It CREATES data in Clínica Sonrisa: services are archived at the end and
// the branch (not deletable) is named e2e-smoke-<ts>.
const COMPANY_MANAGER = "empresa@clinica-sonrisa.ceiba.test";
const stamp = Date.now();
const branchName = `e2e-smoke-${stamp}`;
const serviceName = `e2e-smoke-servicio-${stamp}`;
const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

/** Records console errors and failed requests for the whole test; asserted at the end. */
function watch(page: Page) {
  const problems: string[] = [];
  // The anonymous session probe before login answers 401 by design (and Chrome logs it as a console error).
  let anonymousProbes = 0;
  page.on("console", (message) => {
    if (message.type() !== "error") return;
    if (/status of 401/.test(message.text()) && anonymousProbes-- > 0) return;
    problems.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => problems.push(`pageerror: ${error.message}`));
  // A full navigation (page.goto) aborts the requests still in flight: that is not a failure of the app.
  page.on("requestfailed", (request) => {
    const reason = request.failure()?.errorText ?? "";
    if (reason !== "net::ERR_ABORTED")
      problems.push(`requestfailed: ${request.method()} ${request.url()} (${reason})`);
  });
  page.on("response", (response) => {
    if (response.status() === 401 && response.url().endsWith("/api/v1/auth/session")) {
      anonymousProbes += 1;
      return;
    }
    if (response.status() >= 400)
      problems.push(`http ${response.status()}: ${response.request().method()} ${response.url()}`);
  });
  return problems;
}

async function createService(page: Page, name: string) {
  await nav(page).getByRole("link", { name: "Servicios" }).click();
  await page.getByRole("button", { name: "Nuevo servicio" }).click();
  const panel = page.getByRole("complementary", { name: "Nuevo servicio" });
  await panel.getByLabel("Nombre").fill(name);
  await panel.getByLabel("Duración (minutos)").fill("30");
  await panel.getByLabel("Precio (USD)").fill("99");
  await panel.getByRole("button", { name: "Crear servicio" }).click();
  await expect(page.getByRole("button", { name: `Editar ${name}` })).toBeVisible();
}

async function noHorizontalOverflow(page: Page) {
  expect(await horizontalOverflow(page)).toBeLessThanOrEqual(0);
}

test.describe.configure({ mode: "serial" });

let branchScheduleUrl = "";

test("AC5: crear una sucursal aterriza en su horario con el estado vacío de cerrada", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, COMPANY_MANAGER);
  await nav(page).getByRole("link", { name: "Sucursales" }).click();
  await page.getByRole("button", { name: "Nueva sucursal" }).click();
  const panel = page.getByRole("complementary", { name: "Nueva sucursal" });
  await panel.getByLabel("Nombre").fill(branchName);
  await panel.getByRole("button", { name: "Crear sucursal" }).click();

  await expect(page).toHaveURL(/\/branches\/[^/]+\/schedule$/);
  branchScheduleUrl = new URL(page.url()).pathname;
  await expect(page.getByRole("heading", { name: `Horario de ${branchName}` })).toBeVisible();
  await expect(
    page.getByRole("heading", {
      name: "Configure el horario: la sucursal está cerrada hasta entonces",
    }),
  ).toBeVisible();
  await shot(page, testInfo, "20-ac5-sucursal-cerrada-hasta-configurar");
  expect(problems).toEqual([]);
});

test("AC3: franjas que se cruzan se marcan antes de enviar y no se dispara el PUT", async ({
  page,
}, testInfo) => {
  test.skip(!branchScheduleUrl, "requires the branch from AC5");
  const problems = watch(page);
  const puts: string[] = [];
  page.on("request", (request) => {
    if (request.method() === "PUT") puts.push(request.url());
  });
  await signIn(page, COMPANY_MANAGER);
  await expect(nav(page)).toBeVisible();
  await page.goto(branchScheduleUrl);
  await expect(page.getByRole("heading", { name: `Horario de ${branchName}` })).toBeVisible();

  const monday = page.getByRole("group", { name: "Lunes" });
  await monday.getByRole("button", { name: "Agregar franja" }).click();
  await monday.getByRole("button", { name: "Agregar franja" }).click();
  const starts = monday.getByLabel("Inicio");
  const ends = monday.getByLabel("Fin");
  await starts.nth(0).fill("09:00");
  await ends.nth(0).fill("12:00");
  await starts.nth(1).fill("11:00");
  await ends.nth(1).fill("14:00");
  await page.getByRole("button", { name: "Guardar horario" }).click();

  await expect(monday.getByRole("alert").first()).toContainText(
    "Esta franja se cruza con otra del mismo día.",
  );
  await expect(starts.nth(0)).toHaveAttribute("aria-invalid", "true");
  await expect(starts.nth(1)).toHaveAttribute("aria-invalid", "true");
  await shot(page, testInfo, "21-ac3-franjas-cruzadas");
  expect(puts, "no PUT while the slots overlap").toEqual([]);

  // Fixing the overlap lets the save through (and leaves the branch with a real schedule).
  await ends.nth(0).fill("11:00");
  await starts.nth(1).fill("11:00");
  const saved = page.waitForResponse(
    (response) => response.request().method() === "PUT" && response.url().includes("schedule"),
  );
  await page.getByRole("button", { name: "Guardar horario" }).click();
  expect((await saved).status()).toBe(200);
  await expect(page.getByText("Horario guardado.")).toBeVisible();
  expect(problems).toEqual([]);
});

test("AC4: un servicio archivado sale de Activos y se restaura desde Archivados", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, COMPANY_MANAGER);
  await createService(page, serviceName);
  try {
    await page.getByRole("button", { name: `Archivar ${serviceName}` }).click();
    await expect(page.getByRole("button", { name: `Editar ${serviceName}` })).toHaveCount(0);

    const filters = page.getByRole("group", { name: "Estado de los servicios" });
    await filters.getByRole("button", { name: "Archivados" }).click();
    await expect(page.getByText(serviceName)).toBeVisible();
    await shot(page, testInfo, "22-ac4-archivados");
    await page.getByRole("button", { name: `Restaurar ${serviceName}` }).click();
    await expect(page.getByText(serviceName)).toHaveCount(0);

    await filters.getByRole("button", { name: "Activos" }).click();
    await expect(page.getByRole("button", { name: `Editar ${serviceName}` })).toBeVisible();
    await shot(page, testInfo, "23-ac4-restaurado-en-activos");
  } finally {
    // Leave it archived (from the Activos list, wherever the flow stopped).
    await page
      .getByRole("group", { name: "Estado de los servicios" })
      .getByRole("button", { name: "Activos" })
      .click();
    const archive = page.getByRole("button", { name: `Archivar ${serviceName}` });
    if (await archive.isVisible().catch(() => false)) await archive.click();
    await expect(page.getByRole("button", { name: `Editar ${serviceName}` })).toHaveCount(0);
  }
  expect(problems).toEqual([]);
});

test("shell: menú lateral contraíble y ContextPanel con aria-expanded/aria-controls", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await page.setViewportSize({ width: 1280, height: 800 });
  await signIn(page, COMPANY_MANAGER);
  await nav(page).getByRole("link", { name: "Servicios" }).click();

  const collapse = page.getByRole("button", { name: "Contraer menú" });
  await expect(collapse).toHaveAttribute("aria-expanded", "true");
  const sidebarId = await collapse.getAttribute("aria-controls");
  expect(sidebarId).toBeTruthy();
  await expect(page.locator(`#${sidebarId}`)).toBeVisible();
  await collapse.click();

  const expand = page.getByRole("button", { name: "Expandir menú" });
  await expect(expand).toHaveAttribute("aria-expanded", "false");
  await expect(page.locator("[data-slot=app-frame]")).toHaveAttribute("data-collapsed", "true");
  // In the rail the links keep their name through aria-label.
  for (const name of ["Servicios", "Profesionales", "Recursos", "Sucursales"]) {
    await expect(nav(page).getByRole("link", { name })).toHaveAttribute("aria-label", name);
  }
  await shot(page, testInfo, "24-shell-menu-contraido");
  await expand.click();
  await expect(page.getByRole("button", { name: "Contraer menú" })).toHaveAttribute(
    "aria-expanded",
    "true",
  );

  // ContextPanel.
  await page.getByRole("button", { name: "Nuevo servicio" }).click();
  const panel = page.getByRole("complementary", { name: "Nuevo servicio" });
  await expect(panel).toBeVisible();
  const close = panel.getByRole("button", { name: "Cerrar el panel" });
  await expect(close).toHaveAttribute("aria-expanded", "true");
  await expect(close).toHaveAttribute("aria-controls", (await panel.getAttribute("id")) ?? "");
  await shot(page, testInfo, "25-shell-context-panel-abierto");
  await close.click();
  await expect(panel).toHaveCount(0);
  expect(problems).toEqual([]);
});

test("360 px: servicios y panel sin desborde horizontal", async ({ page }, testInfo) => {
  test.skip(!branchScheduleUrl, "requires the branch from AC5");
  const problems = watch(page);
  await page.setViewportSize({ width: 360, height: 740 });
  await signIn(page, COMPANY_MANAGER);
  await expect(nav(page)).toBeVisible();

  await nav(page).getByRole("link", { name: "Servicios" }).click();
  await expect(page.getByRole("heading", { name: "Servicios", level: 1 })).toBeVisible();
  await noHorizontalOverflow(page);
  await shot(page, testInfo, "30-360-servicios");

  await page.getByRole("button", { name: "Nuevo servicio" }).click();
  const panel = page.getByRole("complementary", { name: "Nuevo servicio" });
  await expect(panel).toBeVisible();
  const box = await panel.boundingBox();
  expect(box && box.x >= 0 && box.x + box.width <= 360).toBe(true);
  await noHorizontalOverflow(page);
  await shot(page, testInfo, "31-360-panel-nuevo-servicio");
  await panel.getByRole("button", { name: "Cerrar el panel" }).click();

  expect(problems).toEqual([]);
});

test("360 px: horario semanal con franjas sin desborde horizontal", async ({ page }, testInfo) => {
  test.skip(!branchScheduleUrl, "requires the branch from AC5");
  const problems = watch(page);
  await page.setViewportSize({ width: 360, height: 740 });
  await signIn(page, COMPANY_MANAGER);
  await expect(nav(page)).toBeVisible();
  await page.goto(branchScheduleUrl);
  await expect(page.getByRole("heading", { name: `Horario de ${branchName}` })).toBeVisible();
  await expect(page.getByRole("group", { name: "Lunes" }).getByLabel("Inicio")).toHaveCount(2);
  await shot(page, testInfo, "32-360-horario-sucursal-desborde");
  await noHorizontalOverflow(page);
  expect(problems).toEqual([]);
});
