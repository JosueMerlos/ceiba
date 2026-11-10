// Presupuesto de tamaño del bundle (ADR-0015): lo que la página de reserva descarga ANTES de poder pintar.
// Lee el manifest de Vite (build.manifest: true): la entrada y sus imports estáticos, recursivamente. Los imports
// dinámicos son bajo demanda y no cuentan. Mide gzip, que es lo que viaja por la red.
//
//   node packages/config/bundle-budget.mjs apps/booking/dist 150
import { readFileSync } from "node:fs";
import { join } from "node:path";
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

if (import.meta.url === `file://${process.argv[1]}`) {
  const [distDir, limit] = process.argv.slice(2);
  if (!distDir || !limit) {
    console.error("uso: bundle-budget.mjs <dist> <límite en KiB>");
    process.exit(2);
  }
  const result = checkBudget(criticalJs(distDir), Number(limit));
  (result.ok ? console.warn : console.error)(result.message);
  process.exit(result.ok ? 0 : 1);
}
