import { expect, test, type Page } from "@playwright/test";
import {
  DON_EFRAIN,
  RECEPTION,
  bookNewCustomer,
  cancelIfPresent,
  nextWorkingDay,
  openAgenda,
  uniquePhone,
} from "../tests/agenda-helpers";
import { horizontalOverflow, shot, signIn } from "../tests/helpers";

// UI QA smoke for customers: the profile's history in the branch's zone whatever the browser's, the screens at desktop
// and phone width, and the import screen. It books one appointment for a new customer and cancels it at the end.
const MANAGER = "gerente@barberia-guegu.ceiba.test";
const FAR_ZONE = "Asia/Tokyo";
const PHONE_WIDTH = { width: 360, height: 780 };

const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

async function openProfile(page: Page, phone: string, customer: string) {
  await nav(page).getByRole("link", { name: "Clientes" }).click();
  await page.getByRole("searchbox", { name: "Buscar clientes" }).fill(phone);
  await page.getByRole("link", { name: customer }).click();
  await expect(page.getByRole("heading", { level: 1, name: customer })).toBeVisible();
}

/** Dates of the history rows, once the one appointment of this run has loaded. */
async function historyDates(page: Page) {
  const cells = page
    .getByRole("region", { name: "Historial" })
    .getByRole("row")
    .locator("td:first-child");
  await expect(cells).toHaveCount(1);
  return cells.allTextContents();
}

test("ficha de cliente: historial en la zona de la sucursal, escritorio y 360 px", async ({
  page,
  browser,
}, testInfo) => {
  const stamp = Date.now();
  const customer = `qa-cliente-${stamp}`;
  const phone = uniquePhone(stamp);
  const day = nextWorkingDay();

  await openAgenda(page, RECEPTION, day);
  await bookNewCustomer(page, {
    professional: DON_EFRAIN,
    service: "Corte clásico",
    customer,
    phone,
  });
  try {
    await openProfile(page, phone, customer);
    await expect(page.getByRole("region", { name: "Próxima cita" })).toBeVisible();
    await expect(page.getByText("Solo las citas de")).toBeVisible();
    const local = await historyDates(page);
    expect(local).toHaveLength(1);
    await shot(page, testInfo, "30-ficha-cliente-escritorio");

    // Same profile from a browser in Tokyo: the dates do not move.
    const far = await browser.newContext({ locale: "es-NI", timezoneId: FAR_ZONE });
    const farPage = await far.newPage();
    await signIn(farPage, RECEPTION);
    await expect(nav(farPage)).toBeVisible();
    await openProfile(farPage, phone, customer);
    expect(await historyDates(farPage)).toEqual(local);
    await far.close();

    await page.setViewportSize(PHONE_WIDTH);
    await shot(page, testInfo, "31-ficha-cliente-360");
    expect(await horizontalOverflow(page)).toBeLessThanOrEqual(0);
  } finally {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(`/agenda?date=${day}`);
    await cancelIfPresent(page, customer);
  }
});

test("lista de clientes e importación a 360 px", async ({ page }, testInfo) => {
  await signIn(page, MANAGER);
  await expect(nav(page)).toBeVisible();
  await page.setViewportSize(PHONE_WIDTH);
  await page.goto("/customers");
  await expect(page.getByRole("heading", { level: 1, name: "Clientes" })).toBeVisible();
  await shot(page, testInfo, "32-lista-clientes-360");

  await page.goto("/customers/import");
  await page.getByRole("radio", { name: "Clientes" }).check();
  await expect(
    page.getByRole("link", { name: "Descargar la plantilla de clientes" }),
  ).toBeVisible();
  await page.getByLabel("Archivo CSV").setInputFiles({
    name: "muestra.csv",
    mimeType: "text/csv",
    buffer: Buffer.from("nombre;telefono\r\nRevisión visual;123\r\n", "latin1"),
  });
  await expect(page.getByRole("region", { name: "Resumen del archivo" })).toBeVisible();
  await shot(page, testInfo, "33-importacion-360");
  expect(await horizontalOverflow(page)).toBeLessThanOrEqual(0);
});
