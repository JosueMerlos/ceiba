import { expect, test, type Page } from "@playwright/test";
import { shot, signIn } from "./helpers";

// Catalog flows against the real environment. Unlike the read-only specs, this one CREATES data (a service, a
// professional and a branch) and archives what it can: a branch cannot be deleted, so it carries a timestamped name.
// It runs in Clínica Sonrisa because the panel spec expects Barbería to keep a single branch.
const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

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

    // Service: created in the modal; the row opens a read-only detail.
    await nav(page).getByRole("link", { name: "Servicios" }).click();
    await page.getByRole("button", { name: "Nuevo servicio" }).click();
    const serviceDialog = page.getByRole("dialog", { name: "Nuevo servicio" });
    await serviceDialog.getByLabel("Nombre").fill(serviceName);
    await serviceDialog
      .getByRole("group", { name: "Duraciones frecuentes" })
      .getByRole("button", { name: "45 min", exact: true })
      .click();
    await serviceDialog.getByLabel("Precio (USD)").fill("150");
    await serviceDialog.getByRole("button", { name: "Crear servicio" }).click();
    await expect(serviceDialog).toHaveCount(0);
    await expect(page.getByRole("button", { name: `Ver ${serviceName}` })).toBeVisible();
    await shot(page, testInfo, "10-catalogo-servicio-creado");

    try {
      // Professional: the profile step creates them; services, branch and hours follow as steps of the same modal.
      await nav(page).getByRole("link", { name: "Profesionales" }).click();
      await page.getByRole("button", { name: "Nuevo profesional" }).click();
      const dialog = page.getByRole("dialog", { name: "Nuevo profesional" });
      await dialog.getByLabel("Nombre para mostrar").fill(professionalName);
      await dialog.getByRole("button", { name: "Crear y continuar" }).click();

      const steps = page.getByRole("dialog", { name: professionalName });
      await expect(steps.getByRole("listitem").filter({ hasText: "Servicios" })).toHaveAttribute(
        "aria-current",
        "step",
      );
      await steps.getByLabel("Buscar servicio").fill(serviceName);
      await steps.getByRole("checkbox", { name: serviceName }).click();
      await steps.getByRole("button", { name: "Guardar y continuar" }).click();

      await steps.getByRole("checkbox", { name: "Clínica Sonrisa Central" }).click();
      await expect(page.getByText("Profesional asignado a la sucursal.")).toBeVisible();
      await steps
        .getByRole("group", { name: "Lunes" })
        .getByRole("button", { name: "Agregar franja" })
        .click();
      await steps.getByRole("button", { name: "Guardar y continuar" }).click();
      await expect(page.getByText("Horario guardado.")).toBeVisible();
      await shot(page, testInfo, "11-catalogo-profesional-con-horario");
      await steps.getByRole("button", { name: "Terminar" }).click();
      await expect(steps).toHaveCount(0);
      await expect(
        page.getByRole("row").filter({ hasText: professionalName }).getByText("1 servicio"),
      ).toBeVisible();

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
      // The list may still be loading, and the professional may not exist if the flow failed early: wait, then archive.
      const archiveProfessional = page.getByRole("button", {
        name: `Archivar ${professionalName}`,
      });
      await archiveProfessional.waitFor({ timeout: 5_000 }).then(
        () => archiveProfessional.click(),
        () => undefined,
      );
      await expect(page.getByRole("button", { name: `Ver ${professionalName}` })).toHaveCount(0);

      await nav(page).getByRole("link", { name: "Servicios" }).click();
      const archiveService = page.getByRole("button", { name: `Archivar ${serviceName}` });
      await archiveService.click();
      await expect(page.getByRole("button", { name: `Ver ${serviceName}` })).toHaveCount(0);
    }
  });
});

test.describe("catálogo: gerente de sucursal (AC2)", () => {
  test("edita la duración de su sucursal y ve el precio como texto, sin campo", async ({
    page,
  }, testInfo) => {
    await signIn(page, "gerente@barberia-guegu.ceiba.test");
    await nav(page).getByRole("link", { name: "Servicios" }).click();

    await page.getByRole("button", { name: "Ver Corte clásico" }).click();
    const detail = page.getByRole("complementary", { name: "Corte clásico" });
    const override = detail.getByRole("region", { name: "En Sucursal Centro" });
    await expect(override.getByLabel("Duración en esta sucursal (minutos)")).toBeEditable();
    await expect(override.getByText("Precio en esta sucursal")).toBeVisible();
    await expect(override.getByRole("textbox", { name: /Precio/ })).toHaveCount(0);
    // The service itself stays read-only for this role: no edit button and no "Nuevo servicio".
    await expect(detail.getByRole("button", { name: "Editar servicio" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Nuevo servicio" })).toHaveCount(0);
    await shot(page, testInfo, "13-catalogo-override-gerente");
  });
});
