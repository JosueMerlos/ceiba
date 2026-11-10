import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";
import { afterEach, describe, expect, it } from "vitest";
import { checkBudget, checkBudgets, criticalJs } from "../bundle-budget.mjs";

// Presupuesto de booking (ADR-0015): el JS CRÍTICO (entrada + lo que importa estáticamente) debe pesar < 150 KiB gzip.
const dirs: string[] = [];
afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })));

/** Un dist de Vite falso: manifest.json + archivos con el contenido indicado. */
function fakeDist(files: Record<string, string>, manifest: Record<string, object>) {
  const dir = mkdtempSync(join(tmpdir(), "bundle-"));
  dirs.push(dir);
  mkdirSync(join(dir, "assets"), { recursive: true });
  mkdirSync(join(dir, ".vite"), { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(join(dir, name), content);
  writeFileSync(join(dir, ".vite/manifest.json"), JSON.stringify(manifest));
  return dir;
}

// Texto pseudoaleatorio: se comprime poco, así el tamaño gzip es previsible.
const noise = (length: number) =>
  Array.from({ length }, (_, i) =>
    String.fromCharCode(33 + ((i * 7919 + (i >> 3) * 104729) % 90)),
  ).join("");

describe("criticalJs", () => {
  it("suma el gzip de la entrada y de sus imports estáticos", () => {
    const entry = "console.log(1);".repeat(50);
    const vendor = "export const a = 1;".repeat(50);
    const dist = fakeDist(
      { "assets/index.js": entry, "assets/vendor.js": vendor },
      {
        "index.html": { file: "assets/index.js", isEntry: true, imports: ["vendor.js"] },
        "vendor.js": { file: "assets/vendor.js" },
      },
    );

    const { bytes, files } = criticalJs(dist);

    expect(files.sort()).toEqual(["assets/index.js", "assets/vendor.js"]);
    expect(bytes).toBe(gzipSync(entry).length + gzipSync(vendor).length);
  });

  it("no cuenta los imports dinámicos (se cargan bajo demanda)", () => {
    const dist = fakeDist(
      { "assets/index.js": "a".repeat(100), "assets/lazy.js": noise(5000) },
      {
        "index.html": { file: "assets/index.js", isEntry: true, dynamicImports: ["lazy.js"] },
        "lazy.js": { file: "assets/lazy.js", isDynamicEntry: true },
      },
    );

    expect(criticalJs(dist).files).toEqual(["assets/index.js"]);
  });

  it("cuenta cada archivo una sola vez aunque varios lo importen", () => {
    const dist = fakeDist(
      {
        "assets/index.js": "x".repeat(100),
        "assets/a.js": "y".repeat(100),
        "assets/shared.js": "z".repeat(100),
      },
      {
        "index.html": { file: "assets/index.js", isEntry: true, imports: ["a.js", "shared.js"] },
        "a.js": { file: "assets/a.js", imports: ["shared.js"] },
        "shared.js": { file: "assets/shared.js" },
      },
    );

    expect(criticalJs(dist).files).toHaveLength(3);
  });
});

describe("checkBudget", () => {
  it("pasa por debajo del límite", () => {
    expect(checkBudget({ bytes: 100 * 1024, files: [] }, 150).ok).toBe(true);
  });

  it("falla por encima del límite y lo explica", () => {
    const result = checkBudget({ bytes: 151 * 1024, files: ["assets/index.js"] }, 150);

    expect(result.ok).toBe(false);
    expect(result.message).toMatch(/151\.0 KiB.*150 KiB/);
  });

  it("el límite exacto pasa", () => {
    expect(checkBudget({ bytes: 150 * 1024, files: [] }, 150).ok).toBe(true);
  });
});

describe("checkBudgets (un presupuesto por app, en un solo archivo)", () => {
  it("evalúa cada app contra su límite y reporta todas", () => {
    const small = fakeDist(
      { "assets/index.js": "a".repeat(100) },
      { "index.html": { file: "assets/index.js", isEntry: true } },
    );
    const big = fakeDist(
      { "assets/index.js": noise(60_000) },
      { "index.html": { file: "assets/index.js", isEntry: true } },
    );

    const results = checkBudgets(
      { booking: { dist: small, limitKiB: 1 }, panel: { dist: big, limitKiB: 1 } },
      "/",
    );

    expect(results.map((result) => [result.name, result.ok])).toEqual([
      ["booking", true],
      ["panel", false],
    ]);
    expect(results[1]!.message).toMatch(/SUPERA/);
  });
});
