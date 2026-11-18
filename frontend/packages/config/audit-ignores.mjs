// Policy for advisories ignored by `pnpm audit`: pnpm has no expiry, so an ignore would otherwise be permanent.
// Every advisory in pnpm's effective config must have one entry in the audit.ignore block of pnpm-workspace.yaml:
//   audit:
//     ignore:
//       - GHSA-xxxx-xxxx-xxxx # revisar: AAAA-MM-DD | motivo: why it does not apply and what unblocks it
// Starting from the effective config covers every way of declaring an ignore that pnpm resolves into it (any YAML
// spelling, environment variables, global config). The block is read as text because YAML parsers discard comments;
// any other spelling of it yields no entries, so its advisories fail.
//
//   pnpm config get audit --json | node packages/config/audit-ignores.mjs pnpm-workspace.yaml
import { readFileSync } from "node:fs";

const LIST_ENTRY = /^\s*-\s+["']?(?<id>[^\s"'#]+)["']?\s*(?:#(?<comment>.*))?$/;
const POLICY = /^\s*revisar:\s*(?<date>\S+)\s*\|\s*motivo:\s*\S/;

function isCalendarDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().startsWith(value);
}

function ignoreEntries(workspaceYaml) {
  const lines = workspaceYaml.split(/\r\n|\r|\n/);
  const start = lines.findIndex(
    (line, index) => /^audit:\s*$/.test(line) && /^\s+ignore:\s*$/.test(lines[index + 1] ?? ""),
  );
  if (start === -1) return [];

  const entries = [];
  for (const line of lines.slice(start + 2)) {
    const entry = line.match(LIST_ENTRY)?.groups;
    if (!entry) break;
    entries.push(entry);
  }
  return entries;
}

function violationFor(id, entries, today) {
  const matches = entries.filter((entry) => entry.id === id);
  if (matches.length > 1) return `${id}: aparece más de una vez en audit.ignore`;

  const date = matches[0]?.comment?.match(POLICY)?.groups.date;
  if (!date) return `${id}: falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea`;
  if (!isCalendarDate(date)) return `${id}: fecha de revisión inválida '${date}'`;
  return date < today ? `${id}: fecha de revisión vencida (${date})` : null;
}

/**
 * @param {string} output of `pnpm config get audit --json`
 * @returns {string[]} advisories pnpm will ignore
 * @throws when the output is not the expected shape: an unreadable config must not pass as "nothing ignored"
 */
export function parseIgnoredAdvisories(output) {
  const config = JSON.parse(output);
  if (config === null) return [];

  const ignore = config.ignore ?? [];
  const isValid =
    typeof config === "object" &&
    !Array.isArray(config) &&
    Array.isArray(ignore) &&
    ignore.every((id) => typeof id === "string");
  if (!isValid) throw new Error(`Configuración de audit inesperada: ${output}`);
  return ignore;
}

/**
 * @param {string} workspaceYaml content of pnpm-workspace.yaml
 * @param {string[]} ignoredAdvisories advisories pnpm will ignore
 * @param {string} today AAAA-MM-DD
 * @returns {string[]} one message per violation; empty when every ignore complies
 */
export function auditIgnoreViolations(workspaceYaml, ignoredAdvisories, today) {
  const entries = ignoreEntries(workspaceYaml);
  return [...new Set(ignoredAdvisories)]
    .map((id) => violationFor(id, entries, today))
    .filter((violation) => violation !== null);
}

if (import.meta.main) {
  const [file] = process.argv.slice(2);
  if (!file) {
    console.error("uso: pnpm config get audit --json | audit-ignores.mjs <pnpm-workspace.yaml>");
    process.exit(2);
  }
  const today = new Date().toISOString().slice(0, 10);
  const ignored = parseIgnoredAdvisories(readFileSync(0, "utf8"));
  const violations = auditIgnoreViolations(readFileSync(file, "utf8"), ignored, today);
  for (const violation of violations) console.error(violation);
  process.exit(violations.length === 0 ? 0 : 1);
}
