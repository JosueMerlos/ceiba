import { expect, test, type Page } from "@playwright/test";
import { RECEPTION } from "../tests/agenda-helpers";
import { shot, signIn } from "../tests/helpers";

// UI QA smoke for loading i18n per namespace: startup asks for no module namespace, each lazy route asks for its own
// when it opens, and no screen paints a raw key (the panel warns "Clave de i18n inexistente" on any missing key).
const MARTA = "marta@salud-estilo.ceiba.test";
const MODULE_NAMESPACES = ["appointments", "branding", "customers", "imports"] as const;
// Dev server: the source file; production build: its own chunk.
const NAMESPACE_REQUEST = new RegExp(
  `(?:locales/es-NI/|assets/)(${MODULE_NAMESPACES.join("|")})[-.]`,
);

function watchI18n(page: Page) {
  const requested = new Set<string>();
  const missingKeys: string[] = [];
  page.on("request", (request) => {
    const match = NAMESPACE_REQUEST.exec(request.url());
    if (match) requested.add(match[1]!);
  });
  page.on("console", (message) => {
    if (message.text().includes("Clave de i18n inexistente")) missingKeys.push(message.text());
  });
  return { requested, missingKeys };
}

const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

async function open(page: Page, link: string, heading: string) {
  await nav(page).getByRole("link", { name: link, exact: true }).click();
  await expect(page.getByRole("heading", { level: 1, name: heading })).toBeVisible();
}

test("dueña: el arranque no trae namespaces de módulo; Marca, Clientes e Importar traen el suyo", async ({
  page,
}, testInfo) => {
  const { requested, missingKeys } = watchI18n(page);

  await signIn(page, MARTA);
  await expect(nav(page)).toBeVisible();
  await page.waitForLoadState("networkidle");
  expect([...requested]).toEqual([]);
  await shot(page, testInfo, "01-inicio-sin-namespaces-de-modulo");

  await open(page, "Marca", "Marca de la empresa");
  expect(requested).toContain("branding");
  await shot(page, testInfo, "02-marca");

  await open(page, "Clientes", "Clientes");
  expect(requested).toContain("customers");
  expect(requested).not.toContain("imports");
  await shot(page, testInfo, "03-clientes");

  await page.getByRole("link", { name: "Importar desde CSV" }).first().click();
  await expect.poll(() => requested.has("imports")).toBe(true);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await shot(page, testInfo, "04-importar");

  // Her company has no appointments module: its namespace is never requested.
  expect(requested).not.toContain("appointments");
  expect(missingKeys).toEqual([]);
});

test("recepción: la agenda y Servicios abren con su namespace y sin claves crudas", async ({
  page,
}, testInfo) => {
  const { requested, missingKeys } = watchI18n(page);

  await signIn(page, RECEPTION);
  await expect(nav(page)).toBeVisible();
  await nav(page).getByRole("link", { name: "Agenda", exact: true }).click();
  await expect(page).toHaveURL(/\/agenda$/);
  await expect(page.getByRole("button", { name: "Nueva cita" }).first()).toBeVisible();
  expect(requested).toContain("appointments");
  await shot(page, testInfo, "05-agenda-recepcion");

  await open(page, "Servicios", "Servicios");
  await expect(page.getByRole("table")).toBeVisible();
  await shot(page, testInfo, "06-servicios-recepcion");

  expect(missingKeys).toEqual([]);
});
