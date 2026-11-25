import { expect, test, type Page } from "@playwright/test";
import {
  brandingUrl,
  brandSession,
  computedContrast,
  restoreDemoBranding,
  shot,
  signIn,
  type BrandSession,
} from "./helpers";

// Unlike the other panel specs, this one WRITES: it changes salon-estilo's brand and puts the demo brand back at the end,
// even when an assertion fails.
test.describe.configure({ mode: "serial" });

let session: BrandSession | undefined;
let cleanupPage: Page;

test.beforeAll(async ({ browser }) => {
  cleanupPage = await (await browser.newContext()).newPage();
});

test.afterAll(async () => {
  // A fresh sign-in: the test that failed may have left its own page in any state.
  await signIn(cleanupPage, "marta@salud-estilo.ceiba.test");
  await expect(cleanupPage.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
  session = await brandSession(cleanupPage);
  await restoreDemoBranding(cleanupPage, session);
  await cleanupPage.context().close();
});

test.describe("branding por empresa", () => {
  test("un amarillo #FFFF00 deja texto oscuro legible y el anillo de foco cae al verde de Ceiba (criterio 1)", async ({
    page,
  }, testInfo) => {
    await signIn(page, "marta@salud-estilo.ceiba.test");
    await page
      .getByRole("navigation", { name: "Navegación principal" })
      .getByRole("link", { name: "Marca" })
      .click();
    await expect(page.getByRole("heading", { name: "Marca de la empresa" })).toBeVisible();

    await page.getByLabel("Color principal", { exact: true }).fill("#FFFF00");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Marca guardada").first()).toBeVisible();

    const cta = page.getByRole("button", { name: "Reservar cita" });
    expect(await computedContrast(cta)).toBeGreaterThanOrEqual(4.5);

    const ring = await page.evaluate(() => {
      const style = getComputedStyle(document.documentElement);
      return {
        ring: style.getPropertyValue("--ring").trim().toLowerCase(),
        canopy500: style.getPropertyValue("--palette-canopy-500").trim().toLowerCase(),
      };
    });
    expect(ring.ring).toBe(ring.canopy500);
    expect(ring.ring).toBe("#2f8a66");
    await shot(page, testInfo, "branding-amarillo");
  });

  test("en 1280 × 800 la pantalla de marca no tiene scroll de documento y conserva el panel acoplado", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await signIn(page, "marta@salud-estilo.ceiba.test");
    await page
      .getByRole("navigation", { name: "Navegación principal" })
      .getByRole("link", { name: "Marca" })
      .click();
    await expect(page.getByRole("heading", { name: "Marca de la empresa" })).toBeVisible();
    await expect(page.locator("#branding-edit-panel")).toBeVisible();
    await expect(page.getByRole("button", { name: "Reservar cita" })).toBeVisible();

    const scroll = await page.evaluate(() => ({
      scrollHeight: document.scrollingElement!.scrollHeight,
      innerHeight: window.innerHeight,
    }));
    expect(scroll.scrollHeight).toBeLessThanOrEqual(scroll.innerHeight);
    await shot(page, testInfo, "branding-1280x800-sin-scroll");
  });

  test("una empresa sin marca usa la paleta de la plataforma (criterio 4)", async ({
    page,
  }, testInfo) => {
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
    await shot(page, testInfo, "branding-sin-marca");
  });

  test("un branch_manager no ve la pantalla de marca y el PATCH directo da 403 (criterio 5)", async ({
    page,
  }, testInfo) => {
    // The ids and the token of marta's context are valid for the same company: the 403 comes from the role, not from ids.
    const owner = await page.context().browser()!.newPage();
    await signIn(owner, "marta@salud-estilo.ceiba.test");
    await expect(owner.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
    const target = await brandSession(owner);
    await owner.close();

    await signIn(page, "gerente@salud-estilo.ceiba.test");
    await expect(page.getByRole("heading", { name: /^Hola, / })).toBeVisible();
    await expect(page.getByRole("link", { name: "Marca" })).toHaveCount(0);

    await page.goto("/settings/branding");
    await expect(
      page.getByRole("heading", { name: "No tiene permiso para ver esto" }),
    ).toBeVisible();
    await shot(page, testInfo, "branding-sin-acceso");

    const own = await brandSession(page);
    const response = await page.request.patch(brandingUrl({ ...target, csrf: own.csrf }), {
      multipart: { brand_name: "Intruso" },
      headers: { "X-CSRF-Token": own.csrf },
    });
    expect(response.status()).toBe(403);
  });
});
