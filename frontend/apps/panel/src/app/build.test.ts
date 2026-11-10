// @vitest-environment node
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "vite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

// Criterio 6: en el build de producción el módulo appointments va en un chunk separado del arranque.
interface ManifestEntry {
  file: string;
  src?: string;
  isEntry?: boolean;
  isDynamicEntry?: boolean;
  imports?: string[];
  dynamicImports?: string[];
}

describe("build de producción del panel", () => {
  let outDir: string;
  let manifest: Record<string, ManifestEntry>;

  beforeAll(async () => {
    outDir = mkdtempSync(join(tmpdir(), "panel-build-"));
    await build({
      root: join(import.meta.dirname, "../.."),
      logLevel: "silent",
      build: { outDir, emptyOutDir: true, manifest: true },
    });
    manifest = JSON.parse(readFileSync(join(outDir, ".vite/manifest.json"), "utf8"));
  }, 120_000);

  afterAll(() => rmSync(outDir, { recursive: true, force: true }));

  const read = (file: string) => readFileSync(join(outDir, file), "utf8");
  const entry = () => Object.values(manifest).find((chunk) => chunk.isEntry)!;

  it("el módulo appointments es un chunk dinámico distinto del de arranque", () => {
    const appointments = Object.values(manifest).find(
      (chunk) => chunk.isDynamicEntry && chunk.src?.includes("modules/appointments/"),
    );

    expect(appointments, "no hay un chunk dinámico para modules/appointments").toBeTruthy();
    expect(appointments!.file).not.toBe(entry().file);
  });

  it("el código de las páginas del módulo no está en el chunk de arranque", () => {
    // `data-module="appointments"` solo lo escribe la página del módulo.
    expect(read(entry().file)).not.toContain("appointments-placeholder");
    const chunk = Object.values(manifest).find((item) =>
      item.src?.includes("modules/appointments/"),
    );
    expect(read(chunk!.file)).toContain("appointments-placeholder");
  });

  it("el arranque solo lo importa dinámicamente (no con un import estático)", () => {
    const chunk = Object.entries(manifest).find(([, item]) =>
      item.src?.includes("modules/appointments/"),
    )!;

    expect(entry().imports ?? []).not.toContain(chunk[0]);
    expect(entry().dynamicImports ?? []).toContain(chunk[0]);
  });
});
