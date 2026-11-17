import { expect, test, type Page } from "@playwright/test";
import {
  brandSession,
  computedContrast,
  restoreDemoBranding,
  shot,
  signIn,
  solidPng,
  SVG_AS_PNG,
  type BrandSession,
} from "../tests/helpers";

// UI QA smoke for the company brand. It writes to salon-estilo and restores the demo brand (and removes the uploaded
// logo) at the end, even on failure.
test.describe.configure({ mode: "serial" });

const MARTA = "marta@salud-estilo.ceiba.test";
const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });
const save = (page: Page) => page.getByRole("button", { name: "Guardar cambios" }).click();
const logoInput = (page: Page) => page.locator('input[type="file"]').first();

async function openBranding(page: Page) {
  await page.goto("/settings/branding");
  await expect(page.getByRole("heading", { name: "Marca de la empresa" })).toBeVisible();
}

let cleanup: Page;

test.beforeAll(async ({ browser }) => {
  cleanup = await (await browser.newContext()).newPage();
});

test.afterAll(async () => {
  await signIn(cleanup, MARTA);
  await expect(nav(cleanup)).toBeVisible();
  await restoreDemoBranding(cleanup, await brandSession(cleanup));
  await cleanup.context().close();
});

test("AC1: #FFFF00 deja texto oscuro con contraste >= 4.5 y anillo de foco canopy-500", async ({
  page,
}, testInfo) => {
  await signIn(page, MARTA);
  await expect(nav(page)).toBeVisible();
  await nav(page).getByRole("link", { name: "Marca" }).click();
  await expect(page.getByRole("heading", { name: "Marca de la empresa" })).toBeVisible();
  await shot(page, testInfo, "ac1-1-pantalla-de-marca");

  await page.getByLabel("Color principal", { exact: true }).fill("#FFFF00");
  await expect(page.getByText(/el texto se mostrará oscuro/)).toBeVisible();
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Marca guardada").first()).toBeVisible();

  const cta = page.getByRole("button", { name: "Reservar cita" });
  const ratio = await computedContrast(cta);
  testInfo.annotations.push({ type: "contraste", description: ratio.toFixed(2) });
  expect(ratio).toBeGreaterThanOrEqual(4.5);

  const ring = await page.evaluate(() =>
    getComputedStyle(document.documentElement).getPropertyValue("--ring").trim().toLowerCase(),
  );
  expect(ring).toBe("#2f8a66");

  // The ring really paints on a keyboard-focused control (not only declared on :root).
  await page.getByLabel("Nombre comercial").focus();
  await page.keyboard.press("Tab");
  await shot(page, testInfo, "ac1-2-amarillo-guardado");
});

test("AC2: un SVG renombrado logo.png se rechaza con el error bajo el campo", async ({
  page,
}, testInfo) => {
  await signIn(page, MARTA);
  await expect(nav(page)).toBeVisible();
  await openBranding(page);
  await logoInput(page).setInputFiles({
    name: "logo.png",
    mimeType: "image/png",
    buffer: SVG_AS_PNG,
  });
  await save(page);

  await expect(page.getByText("El archivo no es una imagen PNG, JPG o WebP.")).toBeVisible();
  await shot(page, testInfo, "ac2-svg-rechazado");
});

test("AC3: un logo reemplazado se ve tras recargar sin limpiar la caché", async ({
  page,
  context,
}, testInfo) => {
  await signIn(page, MARTA);
  await expect(nav(page)).toBeVisible();
  await openBranding(page);

  await logoInput(page).setInputFiles({
    name: "logo-a.png",
    mimeType: "image/png",
    buffer: solidPng(120, 60, [200, 40, 40]),
  });
  await save(page);
  await expect(page.getByText("Marca guardada").first()).toBeVisible();

  const booking = await context.newPage();
  await booking.goto("/c/salon-estilo");
  const logo = booking.getByRole("img", { name: /^Logo de/ });
  await expect(logo).toBeVisible();
  const before = await logo.getAttribute("src");
  await shot(booking, testInfo, "ac3-1-logo-a");

  await openBranding(page);
  await logoInput(page).setInputFiles({
    name: "logo-b.png",
    mimeType: "image/png",
    buffer: solidPng(90, 90, [30, 60, 200]),
  });
  await save(page);
  await expect(page.getByText("Marca guardada").first()).toBeVisible();

  await booking.reload();
  const after = await logo.getAttribute("src");
  expect(after).not.toBeNull();
  expect(after).not.toBe(before);
  await expect
    .poll(() => logo.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBeGreaterThan(0);
  await shot(booking, testInfo, "ac3-2-logo-b-tras-recargar");
});

test("AC4: una empresa sin marca usa la paleta de la plataforma", async ({ page }, testInfo) => {
  await page.goto("/c/clinica-sonrisa");
  await expect(page.locator("main svg")).toBeVisible();
  const result = await page.evaluate(() => {
    const root = document.documentElement;
    const computed = getComputedStyle(root);
    return {
      primary: computed.getPropertyValue("--brand-primary").trim().toLowerCase(),
      canopy600: computed.getPropertyValue("--palette-canopy-600").trim().toLowerCase(),
      inline: root.getAttribute("style") ?? "",
    };
  });
  expect(result.primary).toBe(result.canopy600);
  expect(result.inline).not.toContain("--brand");
  await shot(page, testInfo, "ac4-sin-marca");
});

test("AC5: un branch_manager no ve Marca, la pantalla niega el acceso y el PATCH da 403", async ({
  page,
  browser,
}, testInfo) => {
  const ownerPage = await (await browser.newContext()).newPage();
  await signIn(ownerPage, MARTA);
  await expect(nav(ownerPage)).toBeVisible();
  const target: BrandSession = await brandSession(ownerPage);
  await ownerPage.context().close();

  await signIn(page, "gerente@salud-estilo.ceiba.test");
  await expect(page.getByRole("heading", { name: /^Hola, / })).toBeVisible();
  await expect(page.getByRole("link", { name: "Marca" })).toHaveCount(0);

  await page.goto("/settings/branding");
  await expect(page.getByRole("heading", { name: "No tiene permiso para ver esto" })).toBeVisible();
  await shot(page, testInfo, "ac5-sin-acceso");

  const own = await brandSession(page);
  const response = await page.request.patch(
    `/api/v1/organizations/${target.organizationId}/companies/${target.companyId}/branding`,
    { multipart: { brand_name: "Intruso" }, headers: { "X-CSRF-Token": own.csrf } },
  );
  expect(response.status()).toBe(403);
});
