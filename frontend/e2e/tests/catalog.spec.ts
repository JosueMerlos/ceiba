import { expect, test, type Page } from "@playwright/test";
import { shot, signIn } from "./helpers";

// Catalog flows against the real environment. Unlike the read-only specs, this one CREATES data (a service, a
// professional and a branch) and archives what it can: a branch cannot be deleted, so it carries a timestamped name.
// It runs in Clínica Sonrisa because the panel spec expects Barbería to keep a single branch.
const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

/** A company manager with several branches must choose the one the screen works on. */
async function chooseWorkingBranch(page: Page, name: string) {
  const picker = page.getByRole("combobox", { name: "Sucursal de trabajo" });
  if (await picker.isVisible().catch(() => false)) {
    await picker.click();
    await page.getByRole("option", { name, exact: true }).click();
  }
}

test.describe("catálogo: alta de servicio, profesional y sucursal (AC1, AC6)", () => {
  test("el gerente de empresa configura servicio, profesional con horario y una sucursal nueva", async ({
    page,
  }, testInfo) => {
    const stamp = Date.now();
    const serviceName = `e2e-servicio-${stamp}`;
    const professionalName = `e2e-profesional-${stamp}`;
    const branchName = `e2e-${stamp}`;

    await signIn(page, "empresa@clinica-sonrisa.ceiba.test");
    await expect(nav(page)).toBeVisible();

    // Service.
    await nav(page).getByRole("link", { name: "Servicios" }).click();
    await page.getByRole("button", { name: "Nuevo servicio" }).click();
    const servicePanel = page.getByRole("complementary", { name: "Nuevo servicio" });
    await servicePanel.getByLabel("Nombre").fill(serviceName);
    await servicePanel.getByLabel("Duración (minutos)").fill("30");
    await servicePanel.getByLabel("Precio (USD)").fill("150");
    await servicePanel.getByRole("button", { name: "Crear servicio" }).click();
    await expect(page.getByRole("button", { name: `Editar ${serviceName}` })).toBeVisible();
    await shot(page, testInfo, "10-catalogo-servicio-creado");

    try {
      // Professional: create, give the service, assign to the branch, weekly hours.
      await nav(page).getByRole("link", { name: "Profesionales" }).click();
      await chooseWorkingBranch(page, "Clínica Sonrisa Central");
      await page.getByRole("button", { name: "Nuevo profesional" }).click();
      await page
        .getByRole("complementary", { name: "Nuevo profesional" })
        .getByLabel("Nombre para mostrar")
        .fill(professionalName);
      await page.getByRole("button", { name: "Crear profesional" }).click();

      const panel = page.getByRole("complementary", { name: professionalName });
      const services = panel.getByRole("region", { name: "Servicios que presta" });
      await services.getByRole("checkbox", { name: serviceName }).click();
      await services.getByRole("button", { name: "Guardar servicios" }).click();
      await expect(page.getByText("Servicios guardados.")).toBeVisible();

      const branches = panel.getByRole("region", { name: "Sucursales" });
      await branches.getByRole("checkbox", { name: "Clínica Sonrisa Central" }).click();
      await expect(page.getByText("Profesional asignado a la sucursal.")).toBeVisible();

      const schedule = panel.getByRole("region", { name: "Horario semanal" });
      await schedule
        .getByRole("group", { name: "Lunes" })
        .getByRole("button", { name: "Agregar franja" })
        .click();
      await schedule.getByRole("button", { name: "Guardar horario" }).click();
      await expect(page.getByText("Horario guardado.")).toBeVisible();
      await shot(page, testInfo, "11-catalogo-profesional-con-horario");

      // Branch: a new one lands on its (empty) schedule, where hours are added.
      await nav(page).getByRole("link", { name: "Sucursales" }).click();
      await page.getByRole("button", { name: "Nueva sucursal" }).click();
      await page
        .getByRole("complementary", { name: "Nueva sucursal" })
        .getByLabel("Nombre")
        .fill(branchName);
      await page.getByRole("button", { name: "Crear sucursal" }).click();

      await expect(page).toHaveURL(/\/branches\/[^/]+\/schedule$/);
      await expect(page.getByRole("heading", { name: `Horario de ${branchName}` })).toBeVisible();
      await expect(
        page.getByRole("heading", {
          name: "Configure el horario: la sucursal está cerrada hasta entonces",
        }),
      ).toBeVisible();
      await page
        .getByRole("group", { name: "Lunes" })
        .getByRole("button", { name: "Agregar franja" })
        .click();
      await page.getByRole("button", { name: "Guardar horario" }).click();
      await expect(page.getByText("Horario guardado.")).toBeVisible();
      await shot(page, testInfo, "12-catalogo-sucursal-horario");
    } finally {
      // Clean up what can be cleaned: the professional and the service are archived (the branch stays, named e2e-*).
      await nav(page).getByRole("link", { name: "Profesionales" }).click();
      await chooseWorkingBranch(page, "Clínica Sonrisa Central");
      // The list may still be loading, and the professional may not exist if the flow failed early: wait, then archive.
      const archiveProfessional = page.getByRole("button", {
        name: `Archivar ${professionalName}`,
      });
      await archiveProfessional.waitFor({ timeout: 5_000 }).then(
        () => archiveProfessional.click(),
        () => undefined,
      );
      await expect(page.getByRole("button", { name: `Editar ${professionalName}` })).toHaveCount(0);

      await nav(page).getByRole("link", { name: "Servicios" }).click();
      const archiveService = page.getByRole("button", { name: `Archivar ${serviceName}` });
      await archiveService.click();
      await expect(page.getByRole("button", { name: `Editar ${serviceName}` })).toHaveCount(0);
    }
  });
});

test.describe("catálogo: gerente de sucursal (AC2)", () => {
  test("edita la duración de su sucursal y ve el precio como texto, sin campo", async ({
    page,
  }, testInfo) => {
    await signIn(page, "gerente@barberia-guegu.ceiba.test");
    await nav(page).getByRole("link", { name: "Servicios" }).click();

    await page.getByRole("button", { name: "Editar Corte clásico" }).click();
    const override = page.getByRole("region", { name: "En Sucursal Centro" });
    await expect(override.getByLabel("Duración en esta sucursal (minutos)")).toBeEditable();
    await expect(override.getByText("Precio en esta sucursal")).toBeVisible();
    await expect(override.getByRole("textbox", { name: /Precio/ })).toHaveCount(0);
    // The service itself stays read-only for this role.
    await expect(
      page.getByRole("complementary", { name: "Corte clásico" }).getByLabel("Nombre"),
    ).toBeDisabled();
    await shot(page, testInfo, "13-catalogo-override-gerente");
  });
});
