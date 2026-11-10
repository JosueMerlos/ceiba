// @vitest-environment node
import { criticalJs, checkBudget } from "@ceiba/config/bundle-budget";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "vite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// Presupuesto de ADR-0015: JS crítico de la reserva pública < 150 KiB gzip. Medido en cada corrida de tests y en CI.
export const BUDGET_KIB = 150;

describe("build de producción de booking", () => {
  let outDir: string;

  beforeAll(async () => {
    outDir = mkdtempSync(join(tmpdir(), "booking-build-"));
    await build({
      root: join(import.meta.dirname, ".."),
      logLevel: "silent",
      build: { outDir, emptyOutDir: true, manifest: true },
    });
  }, 120_000);

  afterAll(() => rmSync(outDir, { recursive: true, force: true }));

  it(`el JS crítico pesa menos de ${BUDGET_KIB} KiB gzip`, () => {
    const result = checkBudget(criticalJs(outDir), BUDGET_KIB);

    expect(result.message).toMatch(/^OK/);
  });
});
