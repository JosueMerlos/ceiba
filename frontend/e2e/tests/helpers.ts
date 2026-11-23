import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import zlib from "node:zlib";
import { expect, type Locator, type Page, type TestInfo } from "@playwright/test";

export const PASSWORD = process.env.E2E_PASSWORD ?? "ceiba-demo-2026";

export async function signIn(page: Page, email: string) {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Iniciar sesión" })).toBeVisible();
  await page.getByLabel("Correo electrónico").fill(email);
  await page.getByLabel("Contraseña", { exact: true }).fill(PASSWORD);
  await page.getByRole("button", { name: "Entrar" }).click();
}

/**
 * Evidence folder: the mounted evidence root plus the group of the branch under test (M2.04, error_500_endpoint_org),
 * or Playwright's own output folder when no evidence root is mounted.
 */
function evidenceDir(testInfo: TestInfo): string {
  const root = process.env.E2E_SCREENSHOT_DIR ?? testInfo.outputDir;
  const group = process.env.E2E_EVIDENCE_GROUP;
  return group ? join(root, group) : root;
}

/** Evidence screenshot, in addition to those Playwright saves on failure. */
export async function shot(page: Page, testInfo: TestInfo, name: string) {
  const path = join(evidenceDir(testInfo), `${name}.png`);
  await mkdir(dirname(path), { recursive: true });
  await page.screenshot({ path, fullPage: true });
}

// ---- Company brand helpers (M2.04 specs) ----

/** A valid solid-color PNG generated at runtime, so no binary is committed. */
export function solidPng(
  width: number,
  height: number,
  [r, g, b]: [number, number, number],
): Buffer {
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const head = Buffer.alloc(4);
    head.writeUInt32BE(data.length);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(zlib.crc32(body));
    return Buffer.concat([head, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 2, 0, 0, 0], 8); // 8-bit RGB, no interlace
  const row = Buffer.concat([
    Buffer.from([0]),
    Buffer.from(Array.from({ length: width }, () => [r, g, b]).flat()),
  ]);
  const raw = Buffer.concat(Array.from({ length: height }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

export const SVG_AS_PNG = Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="red"/></svg>',
);

/** Contrast ratio (WCAG) between the computed text color and background color of an element. */
export async function computedContrast(locator: Locator): Promise<number> {
  return locator.evaluate((el) => {
    // A canvas normalizes any CSS color syntax (rgb, oklch, color-mix...) to sRGB bytes.
    const ctx = document.createElement("canvas").getContext("2d", { willReadFrequently: true })!;
    const rgb = (css: string) => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = "#000";
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      return Array.from(ctx.getImageData(0, 0, 1, 1).data.slice(0, 3));
    };
    const lum = ([r, g, b]: number[]) => {
      const f = (c: number) => {
        const s = c / 255;
        return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
      };
      return 0.2126 * f(r!) + 0.7152 * f(g!) + 0.0722 * f(b!);
    };
    const style = getComputedStyle(el);
    const a = lum(rgb(style.color));
    const b = lum(rgb(style.backgroundColor));
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  });
}

export interface BrandSession {
  organizationId: string;
  companyId: string;
  csrf: string;
}

/** Ids of the signed-in context and the CSRF token, read through the page's own session. */
export async function brandSession(page: Page): Promise<BrandSession> {
  const me = await (await page.request.get("/api/v1/me")).json();
  const session = await (await page.request.get("/api/v1/auth/session")).json();
  return {
    organizationId: me.data.context.organization.id,
    companyId: me.data.context.company.id,
    csrf: session.data.csrf_token,
  };
}

export const brandingUrl = ({ organizationId, companyId }: BrandSession) =>
  `/api/v1/organizations/${organizationId}/companies/${companyId}/branding`;

/** Puts salon-estilo's demo brand back (colors, font, name, tagline) and drops any uploaded image. */
export async function restoreDemoBranding(page: Page, session: BrandSession) {
  const form = new FormData();
  form.append("brand_name", "Salón Estilo");
  form.append("tagline", "Su estilo, su momento");
  form.append("primary_color", "#8B2F5C");
  form.append("secondary_color", "#F4E4EC");
  form.append("accent_color", "#C8873A");
  form.append("font_choice", "nunito");
  for (const file of ["logo", "banner", "favicon"]) form.append("remove[]", file);
  const response = await page.request.patch(brandingUrl(session), {
    headers: { "X-CSRF-Token": session.csrf },
    multipart: form,
  });
  expect(response.ok(), `restoring the demo brand answered ${response.status()}`).toBe(true);
}
