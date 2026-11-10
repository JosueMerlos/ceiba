// Bundle size budget: what the booking page downloads BEFORE it can paint.
// Reads the Vite manifest (build.manifest: true): the entry and its static imports, recursively. Dynamic imports are
// on demand and do not count. Measures gzip, which is what travels over the network.
//
//   node packages/config/bundle-budget.mjs apps/booking/dist 150
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { gzipSync } from "node:zlib";

/** @returns {{ bytes: number, files: string[] }} */
export function criticalJs(distDir) {
  const manifest = JSON.parse(readFileSync(join(distDir, ".vite/manifest.json"), "utf8"));
  const seen = new Set();
  const files = [];

  const visit = (key) => {
    if (seen.has(key)) return;
    seen.add(key);
    const chunk = manifest[key];
    if (!chunk) throw new Error(`El manifest no tiene la entrada "${key}"`);
    files.push(chunk.file);
    for (const imported of chunk.imports ?? []) visit(imported);
  };
  for (const [key, chunk] of Object.entries(manifest)) if (chunk.isEntry) visit(key);

  const bytes = files.reduce(
    (total, file) => total + gzipSync(readFileSync(join(distDir, file))).length,
    0,
  );
  return { bytes, files };
}

/** @returns {{ ok: boolean, message: string }} */
export function checkBudget({ bytes, files }, limitKiB) {
  const kib = bytes / 1024;
  const ok = bytes <= limitKiB * 1024;
  const detail = `${kib.toFixed(1)} KiB gzip de JS crítico (límite ${limitKiB} KiB): ${files.join(", ")}`;
  return { ok, message: ok ? `OK ${detail}` : `SUPERA EL PRESUPUESTO: ${detail}` };
}

/**
 * Evaluates several budgets: `{ app: { dist, limitKiB } }` (`dist` paths are relative to `root`).
 * @returns {{ name: string, ok: boolean, message: string }[]}
 */
export function checkBudgets(config, root) {
  return Object.entries(config).map(([name, { dist, limitKiB }]) => {
    const result = checkBudget(criticalJs(resolve(root, dist)), limitKiB);
    return { name, ...result, message: `${name}: ${result.message}` };
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  // Usage: bundle-budget.mjs <bundle-budgets.json>   (paths are relative to the file)
  const [file] = process.argv.slice(2);
  if (!file) {
    console.error("uso: bundle-budget.mjs <bundle-budgets.json>");
    process.exit(2);
  }
  const config = JSON.parse(readFileSync(file, "utf8"));
  const results = checkBudgets(config, resolve(file, ".."));
  for (const result of results) (result.ok ? console.warn : console.error)(result.message);
  process.exit(results.every((result) => result.ok) ? 0 : 1);
}
