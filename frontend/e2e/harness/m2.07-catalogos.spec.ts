import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { expect, test, type Locator, type Page, type TestInfo } from "@playwright/test";
import { shot, signIn } from "../tests/helpers";

// UI QA smoke for the catalogs in modals, one pass per role in Barbería Güegüence. It CREATES a professional and a
// service and archives both at the end, even when an assertion fails.
const COMPANY_MANAGER = "empresa@barberia-guegu.ceiba.test";
const BRANCH_MANAGER = "gerente@barberia-guegu.ceiba.test";
const RECEPTION = "recepcion@barberia-guegu.ceiba.test";
const DON_EFRAIN = "Don Efraín Blandón";

const stamp = Date.now();
const professionalName = `qa-profesional-${stamp}`;
const professionalEmail = `qa-${stamp}@example.com`;
const serviceName = `qa-servicio-${stamp}`;

const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

test.describe.configure({ mode: "serial" });
test.use({ video: "on", viewport: { width: 1280, height: 800 } });

/** Same evidence folder as `shot` (root + branch group), for the per-test video. */
function evidenceDir(testInfo: TestInfo) {
  const root = process.env.E2E_SCREENSHOT_DIR ?? testInfo.outputDir;
  const group = process.env.E2E_EVIDENCE_GROUP;
  return group ? join(root, group) : root;
}

const slug = (title: string) =>
  title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .slice(0, 60)
    .replace(/-+$/, "");

test.afterEach(async ({ page }, testInfo) => {
  const video = page.video();
  await page.close();
  if (!video) return;
  const dir = evidenceDir(testInfo);
  await mkdir(dir, { recursive: true });
  await video.saveAs(join(dir, `m2.07-video-${slug(testInfo.title)}.webm`));
});

test.afterAll(async ({ browser }) => {
  // A fresh session: the test that failed may have left its page anywhere.
  const page = await (await browser.newContext()).newPage();
  await signIn(page, COMPANY_MANAGER);
  await expect(nav(page)).toBeVisible();
  await archiveIfPresent(page, "Profesionales", professionalName);
  await archiveIfPresent(page, "Servicios", serviceName);
  await page.context().close();
});

async function archiveIfPresent(page: Page, section: string, name: string) {
  await nav(page).getByRole("link", { name: section }).click();
  await expect(page.getByRole("heading", { level: 1, name: section })).toBeVisible();
  const archive = page.getByRole("button", { name: `Archivar ${name}` });
  await archive.waitFor({ timeout: 5_000 }).then(
    () => archive.click(),
    () => undefined,
  );
  await expect(page.getByRole("button", { name: `Ver ${name}` })).toHaveCount(0);
}

/** Console errors and failed requests of the whole test; asserted at the end. */
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
      return;
    }
    if (response.status() >= 400)
      problems.push(`http ${response.status()}: ${response.request().method()} ${response.url()}`);
  });
  return problems;
}

/** The modal's save actions: exactly one per tab (the footer's). */
const saveButtons = (dialog: Locator) =>
  dialog.getByRole("button", { name: /^(Guardar|Agregar ausencia|Crear)/ });

const nativeDateTimeInputs = (scope: Locator) =>
  scope.locator('input[type="date"], input[type="time"], input[type="datetime-local"]');

test("AC1-AC4 company_manager: crea el profesional en pasos, omite el resto y edita con un solo guardar por pestaña", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, COMPANY_MANAGER);
  await nav(page).getByRole("link", { name: "Profesionales" }).click();
  await page.getByRole("button", { name: "Nuevo profesional" }).click();

  const dialog = page.getByRole("dialog", { name: "Nuevo profesional" });
  await dialog.getByLabel("Nombre para mostrar").fill(professionalName);
  await dialog.getByLabel("Teléfono (opcional)").fill("8888 1234");
  await dialog.getByLabel("Correo (opcional)").fill(professionalEmail);
  await expect(
    dialog.getByText("Paso 1 de 4. Al continuar, el profesional queda creado."),
  ).toBeVisible();
  await shot(page, testInfo, "m2.07-01-empresa-paso-perfil");

  const created = page.waitForResponse(
    (response) => response.request().method() === "POST" && /\/professionals$/.test(response.url()),
  );
  await dialog.getByRole("button", { name: "Crear y continuar" }).click();
  const response = await created;
  expect(response.status()).toBe(201);
  const body = await response.json();
  expect(body.data.phone).toBe("+50588881234");
  expect(body.data.email).toBe(professionalEmail);

  // Step 2 (services) is reached and the rest can be skipped: the record already exists.
  const steps = page.getByRole("dialog", { name: professionalName });
  const current = steps.locator('li[aria-current="step"]');
  await expect(current).toContainText("Servicios");
  await shot(page, testInfo, "m2.07-02-empresa-paso-servicios");
  for (const label of ["Servicios", "Sucursal y horario", "Ausencias"]) {
    await expect(current).toContainText(label);
    await steps.getByRole("button", { name: "Omitir por ahora" }).click();
  }
  await expect(steps).toHaveCount(0);
  await expect(page.getByRole("button", { name: `Ver ${professionalName}` })).toBeVisible();

  // Edit: tabs, the phone comes back in E.164, and every tab with a form has exactly one save action. With no
  // branch yet, the branch and absence tabs have nothing to save, so their footer offers no button.
  await page.getByRole("button", { name: `Ver ${professionalName}` }).click();
  await page
    .getByRole("complementary", { name: professionalName })
    .getByRole("button", { name: "Editar profesional" })
    .click();
  const edit = page.getByRole("dialog", { name: professionalName });
  await expect(edit.getByLabel("Teléfono (opcional)")).toHaveValue("+50588881234");
  await expect(edit.getByLabel("Correo (opcional)")).toHaveValue(professionalEmail);
  const tabs = edit.getByRole("tab");
  await expect(tabs).toHaveText(["Perfil", "Servicios", "Sucursal y horario", "Ausencias"]);
  const saveCount = { Perfil: 1, Servicios: 1, "Sucursal y horario": 0, Ausencias: 0 };
  for (const [tab, count] of Object.entries(saveCount)) {
    await edit.getByRole("tab", { name: tab }).click();
    await expect(edit.getByRole("tab", { name: tab })).toHaveAttribute("aria-selected", "true");
    await expect(saveButtons(edit), `${count} save action on ${tab}`).toHaveCount(count);
  }
  await edit.getByRole("tab", { name: "Perfil" }).click();
  await shot(page, testInfo, "m2.07-03-empresa-editar-perfil-e164");
  await edit.getByRole("button", { name: "Cerrar", exact: true }).click();
  await expect(edit).toHaveCount(0);
  expect(problems).toEqual([]);
});

test("AC6 company_manager: la categoría «  Uñas  » se ve recortada en la tabla de servicios", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, COMPANY_MANAGER);
  await nav(page).getByRole("link", { name: "Servicios" }).click();
  await page.getByRole("button", { name: "Nuevo servicio" }).click();
  const dialog = page.getByRole("dialog", { name: "Nuevo servicio" });
  await dialog.getByLabel("Nombre").fill(serviceName);
  await dialog.getByRole("combobox", { name: "Categoría (opcional)" }).fill("  Uñas  ");
  await dialog.getByLabel(/^Precio/).fill("120");
  const created = page.waitForResponse(
    (response) => response.request().method() === "POST" && /\/services$/.test(response.url()),
  );
  await dialog.getByRole("button", { name: "Crear servicio" }).click();
  expect((await (await created).json()).data.category).toBe("Uñas");

  const row = page
    .getByRole("row")
    .filter({ has: page.getByRole("button", { name: `Ver ${serviceName}` }) });
  await expect(row.getByText("Uñas", { exact: true })).toBeVisible();
  await shot(page, testInfo, "m2.07-04-empresa-servicio-categoria");
  expect(problems).toEqual([]);
});

test("AC10 company_manager: el formulario de ausencias no usa inputs nativos de fecha u hora", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, COMPANY_MANAGER);
  await nav(page).getByRole("link", { name: "Profesionales" }).click();
  await page.getByRole("button", { name: `Ver ${DON_EFRAIN}` }).click();
  await page
    .getByRole("complementary", { name: DON_EFRAIN })
    .getByRole("button", { name: "Editar profesional" })
    .click();
  const edit = page.getByRole("dialog", { name: DON_EFRAIN });
  await edit.getByRole("tab", { name: "Ausencias" }).click();
  await expect(edit.getByRole("button", { name: "Agregar ausencia" })).toBeVisible();
  await expect(edit.getByText("Desde", { exact: true }).first()).toBeVisible();
  await expect(nativeDateTimeInputs(edit)).toHaveCount(0);
  await shot(page, testInfo, "m2.07-05-empresa-ausencias-sin-inputs-nativos");
  await edit.getByRole("button", { name: "Cerrar", exact: true }).click();
  expect(problems).toEqual([]);
});

test("AC2 branch_manager: edita al profesional sin ver su teléfono ni su correo", async ({
  page,
}, testInfo) => {
  const problems = watch(page);
  await signIn(page, BRANCH_MANAGER);
  await nav(page).getByRole("link", { name: "Profesionales" }).click();
  await expect(page.getByRole("button", { name: "Nuevo profesional" })).toHaveCount(0);
  await page.getByRole("button", { name: `Ver ${DON_EFRAIN}` }).click();
  await page
    .getByRole("complementary", { name: DON_EFRAIN })
    .getByRole("button", { name: "Editar profesional" })
    .click();
  const edit = page.getByRole("dialog", { name: DON_EFRAIN });
  await expect(edit.getByRole("tab").first()).toBeVisible();
  await expect(edit.getByRole("tab", { name: "Perfil" })).toHaveCount(0);
  for (const tab of await edit.getByRole("tab").allTextContents()) {
    await edit.getByRole("tab", { name: tab }).click();
    await expect(edit.getByLabel("Teléfono (opcional)")).toHaveCount(0);
    await expect(edit.getByLabel("Correo (opcional)")).toHaveCount(0);
    await expect(edit).not.toContainText("+505");
    await expect(saveButtons(edit), `one save action on ${tab}`).toHaveCount(1);
  }
  await shot(page, testInfo, "m2.07-06-gerente-editar-sin-contacto");
  await edit.getByRole("button", { name: "Cerrar", exact: true }).click();
  expect(problems).toEqual([]);
});

for (const section of [
  { name: "Servicios", create: "Nuevo servicio", file: "servicios" },
  { name: "Profesionales", create: "Nuevo profesional", file: "profesionales" },
  { name: "Recursos", create: "Nuevo recurso", file: "recursos" },
]) {
  test(`AC8 receptionist: ${section.name} en solo lectura con detalle flotante`, async ({
    page,
  }, testInfo) => {
    const problems = watch(page);
    await signIn(page, RECEPTION);
    await nav(page).getByRole("link", { name: section.name }).click();
    await expect(page.getByRole("heading", { level: 1, name: section.name })).toBeVisible();

    await expect(page.getByText("Solo lectura", { exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: section.create })).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^(Archivar|Restaurar|Editar) / })).toHaveCount(
      0,
    );
    await expect(page.getByRole("columnheader", { name: "Acciones" })).toHaveCount(0);

    const row = page.getByRole("button", { name: /^Ver / }).first();
    const name = ((await row.getAttribute("aria-label")) ?? "").replace(/^Ver /, "");
    await row.click();
    const detail = page.getByRole("complementary", { name });
    await expect(detail).toBeVisible();
    await expect(detail).toHaveAttribute("data-variant", "floating");
    await expect(detail.getByText("Cargando…")).toHaveCount(0);
    await expect(detail.getByRole("button", { name: /^Editar/ })).toHaveCount(0);
    await expect(detail.getByRole("textbox")).toHaveCount(0);
    // No contact of any professional anywhere on the page.
    await expect(page.locator("body")).not.toContainText("+505");
    await expect(page.locator("body")).not.toContainText(/@(?!barberia-guegu)[\w.-]+\.\w+/);
    await shot(page, testInfo, `m2.07-07-recepcion-${section.file}-lectura`);
    expect(problems).toEqual([]);
  });
}
