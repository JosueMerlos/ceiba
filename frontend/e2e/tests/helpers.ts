import { expect, type Page, type TestInfo } from "@playwright/test";

export const PASSWORD = process.env.E2E_PASSWORD ?? "ceiba-demo-2026";

export async function signIn(page: Page, email: string) {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Iniciar sesión" })).toBeVisible();
  await page.getByLabel("Correo electrónico").fill(email);
  await page.getByLabel("Contraseña", { exact: true }).fill(PASSWORD);
  await page.getByRole("button", { name: "Entrar" }).click();
}

/** Evidence screenshot (E2E_SCREENSHOT_DIR), in addition to those Playwright saves on failure. */
export async function shot(page: Page, testInfo: TestInfo, name: string) {
  const dir = process.env.E2E_SCREENSHOT_DIR ?? testInfo.outputDir;
  await page.screenshot({ path: `${dir}/${name}.png`, fullPage: true });
}
