import { expect, test, type Page } from "@playwright/test";
import { nextWorkingDay, openAgenda, RECEPTION, sidePanel } from "../tests/agenda-helpers";
import { shot, signIn } from "../tests/helpers";

// UI QA smoke for the shared layout and fields of the redesign: fixed-height frame, floating context panel, docked
// panel on the brand screen, and the new date and time fields. Read-only: it opens panels but saves nothing.
const MARTA = "marta@salud-estilo.ceiba.test";

const sheet = (page: Page) => page.locator("#contenido-principal");
const width = async (page: Page) => (await sheet(page).boundingBox())!.width;

async function noDocumentScroll(page: Page) {
  return page.evaluate(
    () => document.scrollingElement!.scrollHeight === window.innerHeight && window.scrollY === 0,
  );
}

test("AC6: abrir el panel flotante en la agenda no cambia el ancho de la hoja", async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openAgenda(page, RECEPTION, nextWorkingDay());
  const closed = await width(page);
  await shot(page, testInfo, "ac6-1-agenda-panel-cerrado");

  await page.getByRole("button", { name: "Nueva cita" }).click();
  const panel = sidePanel(page, "Nueva cita");
  await expect(panel).toBeVisible();
  await expect(panel).toHaveAttribute("data-variant", "floating");
  const open = await width(page);
  await shot(page, testInfo, "ac6-2-agenda-panel-flotante");

  expect(open).toBe(closed);
  // The panel floats over the sheet instead of standing next to it.
  const panelBox = (await panel.boundingBox())!;
  const sheetBox = (await sheet(page).boundingBox())!;
  expect(panelBox.x).toBeLessThan(sheetBox.x + sheetBox.width);
});

for (const viewport of [
  { width: 1280, height: 600, name: "escritorio" },
  { width: 360, height: 640, name: "celular" },
]) {
  test(`AC7 (${viewport.name}): el documento no se desplaza y la barra lateral queda quieta`, async ({
    page,
  }, testInfo) => {
    await page.setViewportSize(viewport);
    await openAgenda(page, RECEPTION, nextWorkingDay());
    // The calendar is a lazy chunk: measure once its hours are drawn, not while the sheet is still short.
    await expect(
      page
        .getByText(/5:00\sp\.\sm\./)
        .filter({ visible: true })
        .first(),
    ).toBeAttached();
    const sidebar = page.locator("#barra-lateral");
    const before = (await sidebar.boundingBox())!.y;

    const scrolled = await sheet(page).evaluate((main) => {
      main.scrollTop = main.scrollHeight;
      return main.scrollTop;
    });
    await page.mouse.wheel(0, 2000);

    expect(scrolled, "la agenda debe ser más alta que la ventana").toBeGreaterThan(0);
    expect(await noDocumentScroll(page)).toBe(true);
    expect((await sidebar.boundingBox())!.y).toBe(before);
    await shot(page, testInfo, `ac7-hoja-desplazada-${viewport.name}`);
  });
}

test("Marca conserva el panel acoplado: no tapa la vista previa", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await signIn(page, MARTA);
  await expect(page.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
  await page.goto("/settings/branding");
  await expect(page.getByRole("heading", { name: "Marca de la empresa" })).toBeVisible();

  const panel = page.getByRole("complementary", { name: "Personalizar" });
  await expect(panel).toHaveAttribute("data-variant", "docked");
  const panelBox = (await panel.boundingBox())!;
  const sheetBox = (await sheet(page).boundingBox())!;
  expect(panelBox.x).toBeGreaterThanOrEqual(sheetBox.x + sheetBox.width);
  expect(await noDocumentScroll(page)).toBe(true);
  await shot(page, testInfo, "marca-panel-acoplado");
});

test("campos nuevos: fecha con calendario y hora «9:00 a. m.» sin inputs nativos", async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openAgenda(page, RECEPTION, nextWorkingDay());
  await page.getByRole("button", { name: "Nueva cita" }).click();
  const panel = sidePanel(page, "Nueva cita");

  await panel.getByRole("button", { name: "Fecha" }).click();
  const calendar = page.getByRole("dialog", { name: "Calendario" });
  await expect(calendar.getByRole("grid")).toBeVisible();
  await shot(page, testInfo, "campos-1-selector-de-fecha");
  await page.keyboard.press("Escape");

  expect(
    await page
      .locator('input[type="date"], input[type="time"], input[type="datetime-local"]')
      .count(),
  ).toBe(0);
  await expect(
    page
      .getByText(/\d{1,2}:\d{2}\sa\.\sm\./)
      .filter({ visible: true })
      .first(),
  ).toBeVisible();
  await shot(page, testInfo, "campos-2-horas-con-formato-unico");
});
