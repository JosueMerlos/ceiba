import { expect, test } from "@playwright/test";
import { shot, signIn } from "./helpers";

// login -> context -> navigation, against the real environment (API + panel + proxy).
test.describe("panel: login, contexto y navegación", () => {
  test("una sola organización/empresa/sucursal: entra directo, sin selector (criterio 1)", async ({
    page,
  }, testInfo) => {
    await signIn(page, "rosa@barberia-guegu.ceiba.test");

    const nav = page.getByRole("navigation", { name: "Navegación principal" });
    await expect(nav).toBeVisible();
    await expect(page.getByRole("heading", { name: "Hola, Rosa" })).toBeVisible();
    await expect(page.getByRole("button", { name: /Cambiar el contexto de trabajo/ })).toHaveCount(
      0,
    );
    await shot(page, testInfo, "01-inicio-rosa");

    // The owner sees the summary (counts), not the agenda with appointment details.
    await expect(nav.getByRole("link", { name: "Resumen de citas" })).toBeVisible();
    await expect(nav.getByRole("link", { name: "Agenda" })).toHaveCount(0);
    await nav.getByRole("link", { name: "Resumen de citas" }).click();
    await expect(page.getByRole("heading", { name: "Resumen de citas" })).toBeVisible();
    await expect(page).toHaveURL(/\/agenda\/summary$/);
    await shot(page, testInfo, "02-resumen-rosa");
  });

  test("un receptionist solo ve lo que sus permisos permiten (criterio 4)", async ({
    page,
  }, testInfo) => {
    await signIn(page, "recepcion@barberia-guegu.ceiba.test");

    const nav = page.getByRole("navigation", { name: "Navegación principal" });
    await expect(nav.getByRole("link", { name: "Agenda" })).toBeVisible();
    await expect(nav.getByRole("link", { name: "Resumen de citas" })).toHaveCount(0);
    await nav.getByRole("link", { name: "Agenda" }).click();
    await expect(page.getByRole("heading", { name: "Agenda" })).toBeVisible();
    await shot(page, testInfo, "03-agenda-recepcion");

    // What /me does not offer does not exist: the summary by URL is "not found".
    await page.goto("/agenda/summary");
    await expect(page.getByRole("heading", { name: "No encontramos esta página" })).toBeVisible();
    await shot(page, testInfo, "04-no-encontrado");
  });

  test("varias empresas: aparece el selector y el módulo depende de la empresa (criterios 2 y 3)", async ({
    page,
  }, testInfo) => {
    await signIn(page, "luis@salud-estilo.ceiba.test");

    const nav = page.getByRole("navigation", { name: "Navegación principal" });
    const selector = page.getByRole("button", { name: /Cambiar el contexto de trabajo/ });
    await expect(selector).toContainText("Clínica Dental Sonrisa");
    await expect(nav.getByRole("link", { name: "Resumen de citas" })).toBeVisible();
    await shot(page, testInfo, "05-inicio-luis");

    await selector.click();
    await expect(page.getByRole("menuitemradio", { name: "Salón Estilo" })).toBeVisible();
    await page.waitForTimeout(300); // let the opening animation finish before the screenshot
    await shot(page, testInfo, "06-selector-abierto");
    await page.getByRole("menuitemradio", { name: "Salón Estilo" }).click();

    // Salón Estilo has no appointments module active: no menu item and the URL is "not found".
    await expect(selector).toContainText("Salón Estilo");
    await expect(page.getByText("Su empresa todavía no tiene módulos activos.")).toBeVisible();
    await expect(nav).toHaveCount(0);
    await page.goto("/agenda/summary");
    await expect(page.getByRole("heading", { name: "No encontramos esta página" })).toBeVisible();
    await shot(page, testInfo, "07-empresa-sin-modulo");

    // The server remembers the chosen context (ceiba_context cookie): after reload it is still Salón Estilo.
    await page.reload();
    await expect(
      page.getByRole("button", { name: /Cambiar el contexto de trabajo/ }),
    ).toContainText("Salón Estilo");
  });

  test("sesión expirada: vuelve al login conservando la ruta (criterio 5)", async ({
    page,
    context,
  }, testInfo) => {
    await signIn(page, "recepcion@barberia-guegu.ceiba.test");
    await expect(page.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();

    // The session is lost (cookie deleted = expired or revoked on another device) and an internal path is requested.
    await context.clearCookies();
    await page.goto("/agenda");

    await expect(page.getByRole("heading", { name: "Iniciar sesión" })).toBeVisible();
    await expect(page).toHaveURL(/\/login\?next=%2Fagenda$/);
    await shot(page, testInfo, "08-login-con-retorno");

    await page.getByLabel("Correo electrónico").fill("recepcion@barberia-guegu.ceiba.test");
    await page
      .getByLabel("Contraseña", { exact: true })
      .fill(process.env.E2E_PASSWORD ?? "ceiba-demo-2026");
    await page.getByRole("button", { name: "Entrar" }).click();
    await expect(page.getByRole("heading", { name: "Agenda" })).toBeVisible();
    await expect(page).toHaveURL(/\/agenda$/);
  });

  test("credenciales incorrectas muestran el error en el formulario", async ({
    page,
  }, testInfo) => {
    await page.goto("/");
    await page.getByLabel("Correo electrónico").fill("rosa@barberia-guegu.ceiba.test");
    await page.getByLabel("Contraseña", { exact: true }).fill("incorrecta-123");
    await page.getByRole("button", { name: "Entrar" }).click();

    await expect(page.getByRole("alert")).toHaveText("El correo o la contraseña no son correctos.");
    await shot(page, testInfo, "09-login-error");
  });

  test("cerrar sesión vuelve al login", async ({ page }) => {
    await signIn(page, "rosa@barberia-guegu.ceiba.test");
    await page.getByRole("button", { name: "Cuenta de Rosa Mendoza" }).click();
    await page.getByRole("menuitem", { name: "Cerrar sesión", exact: true }).click();

    await expect(page.getByRole("heading", { name: "Iniciar sesión" })).toBeVisible();
  });

  test("en un móvil la navegación pasa a una fila bajo la cabecera", async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, "recepcion@barberia-guegu.ceiba.test");

    const nav = page.getByRole("navigation", { name: "Navegación principal" });
    await expect(nav.getByRole("link", { name: "Agenda" })).toBeVisible();
    await nav.getByRole("link", { name: "Agenda" }).click();
    await expect(page.getByRole("heading", { name: "Agenda" })).toBeVisible();
    await shot(page, testInfo, "10-movil-agenda");
  });

  test("en 360 px con selector de contexto (Luis) nada se desborda: avatar y menú de cuenta quedan a la vista", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 360, height: 740 });
    await signIn(page, "luis@salud-estilo.ceiba.test");

    const selector = page.getByRole("button", { name: /Cambiar el contexto de trabajo/ });
    await expect(selector).toBeVisible();
    const account = page.getByRole("button", { name: "Cuenta de Luis Ortega" });
    await expect(account).toBeVisible();
    await shot(page, testInfo, "11-movil-luis-360");

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
    const box = await account.boundingBox();
    expect(box!.x + box!.width).toBeLessThanOrEqual(360);
    // The selector keeps an accessible name with the company even when only the icon shows.
    await expect(selector).toHaveAccessibleName(/Clínica Dental Sonrisa/);
  });

  test("dos organizaciones (Ana): al cambiar de organización no queda ningún nombre de la anterior (criterio 2)", async ({
    page,
  }, testInfo) => {
    await signIn(page, "ana@multi-org.ceiba.test");

    const selector = page.getByRole("button", { name: /Cambiar el contexto de trabajo/ });
    await expect(selector).toBeVisible();
    const current = (await selector.textContent()) ?? "";
    const [from, to] = current.includes("Barbería")
      ? ["Barbería", "Café Volcán"]
      : ["Café Volcán", "Barbería"];
    await shot(page, testInfo, "12-ana-organizacion-a");

    await selector.click();
    await page
      .getByRole("menuitemradio", { name: new RegExp(to) })
      .first()
      .click();

    await expect(selector).toContainText(to);
    await expect(page.locator("body")).not.toContainText(from);
    await shot(page, testInfo, "13-ana-organizacion-b");
  });
});
