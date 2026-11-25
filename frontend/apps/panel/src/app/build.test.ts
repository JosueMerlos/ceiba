// @vitest-environment node
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "vite";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { esNI } from "../../../../packages/i18n/src/locales/es-NI";

// In the production build the appointments module ships in a chunk separate from startup.
interface ManifestEntry {
  file: string;
  src?: string;
  isEntry?: boolean;
  isDynamicEntry?: boolean;
  imports?: string[];
  dynamicImports?: string[];
}

const MODULE_ENTRY = "src/modules/appointments/routes/index.tsx";
const CALENDAR_ADAPTER =
  "src/modules/appointments/components/agenda-view/adapters/event-calendar.tsx";
// A class name only the calendar library writes.
const CALENDAR_MARKER = "ec-event";
// The class prefix only react-day-picker writes.
const DAY_PICKER_MARKER = "rdp-";

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
  const criticalChunks = () => {
    const critical = new Set<string>();
    const visit = (key: string) => {
      if (critical.has(key)) return;
      critical.add(key);
      for (const child of manifest[key]?.imports ?? []) visit(child);
    };
    visit(Object.keys(manifest).find((key) => manifest[key]!.isEntry)!);
    return critical;
  };

  it("el módulo appointments es un chunk dinámico distinto del de arranque", () => {
    const appointments = Object.values(manifest).find(
      (chunk) => chunk.isDynamicEntry && chunk.src?.includes("modules/appointments/"),
    );

    expect(appointments, "no hay un chunk dinámico para modules/appointments").toBeTruthy();
    expect(appointments!.file).not.toBe(entry().file);
  });

  it("el código de las páginas del módulo no está en el chunk de arranque", () => {
    // `data-module="appointments"` is written only by the module's page.
    expect(read(entry().file)).not.toContain("appointments-placeholder");
    expect(read(manifest[MODULE_ENTRY]!.file)).toContain("appointments-placeholder");
  });

  it("el arranque solo lo importa dinámicamente (no con un import estático)", () => {
    expect(entry().imports ?? []).not.toContain(MODULE_ENTRY);
    expect(entry().dynamicImports ?? []).toContain(MODULE_ENTRY);
  });

  it("la librería del calendario solo viaja en el chunk de su adaptador", () => {
    const adapter = manifest[CALENDAR_ADAPTER]!;
    const withCalendar = Object.values(manifest).filter(
      (item) => item.file.endsWith(".js") && read(item.file).includes(CALENDAR_MARKER),
    );

    expect(withCalendar.map((item) => item.file)).toEqual([adapter.file]);
    expect(manifest[MODULE_ENTRY]!.imports ?? []).not.toContain(CALENDAR_ADAPTER);
  });

  it("react-day-picker viaja solo en chunks diferidos, fuera del JS crítico", () => {
    const critical = new Set<string>();
    const visit = (key: string) => {
      if (critical.has(key)) return;
      critical.add(key);
      for (const child of manifest[key]?.imports ?? []) visit(child);
    };
    visit(Object.keys(manifest).find((key) => manifest[key]!.isEntry)!);
    const withDayPicker = Object.entries(manifest).filter(
      ([, item]) => item.file.endsWith(".js") && read(item.file).includes(DAY_PICKER_MARKER),
    );

    expect(withDayPicker.length).toBeGreaterThan(0);
    expect(withDayPicker.filter(([key]) => critical.has(key)).map(([, item]) => item.file)).toEqual(
      [],
    );
  });

  it("los textos de los namespaces de módulo no viajan en el JS crítico, sí en un chunk diferido", () => {
    const startup = new Set(["common", "auth", "shell", "errors"]);
    const leaves = (node: unknown): string[] =>
      typeof node === "string"
        ? [node]
        : Object.values(node as Record<string, unknown>).flatMap(leaves);
    const startupTexts = new Set(
      Object.entries(esNI)
        .filter(([namespace]) => startup.has(namespace))
        .flatMap(([, catalog]) => leaves(catalog)),
    );
    // ASCII texts without quotes or backslashes appear verbatim in the minified JS.
    const markers = Object.entries(esNI)
      .filter(([namespace]) => !startup.has(namespace))
      .flatMap(([, catalog]) => leaves(catalog))
      .filter((text) => text.length >= 20 && /^[ -~]+$/.test(text) && !/["'`\\]/.test(text))
      .filter((text) => !startupTexts.has(text));
    const critical = criticalChunks();
    const criticalJs = Object.entries(manifest)
      .filter(([key, item]) => critical.has(key) && item.file.endsWith(".js"))
      .map(([, item]) => read(item.file))
      .join("\n");
    const deferredJs = Object.entries(manifest)
      .filter(([key, item]) => !critical.has(key) && item.file.endsWith(".js"))
      .map(([, item]) => read(item.file))
      .join("\n");

    expect(markers.length).toBeGreaterThan(20);
    expect(markers.filter((text) => criticalJs.includes(text))).toEqual([]);
    expect(markers.filter((text) => !deferredJs.includes(text))).toEqual([]);
  });
});
