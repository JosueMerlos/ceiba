// Policy for advisories ignored by `pnpm audit`: pnpm has no expiry, so an ignore would otherwise be permanent.
// Each entry in pnpm-workspace.yaml must sit on its own line as
//   - GHSA-xxxx-xxxx-xxxx # revisar: AAAA-MM-DD | motivo: why it does not apply and what unblocks it
// Reads the block line by line and rejects anything it does not recognize, so pnpm cannot honor an unchecked ignore.
//
//   node packages/config/audit-ignores.mjs pnpm-workspace.yaml
import { readFileSync } from "node:fs";

const BLOCK_START = /^["']?auditConfig["']?\s*:\s*(?<inline>.*)$/;
const LIST_KEY = /^\s+ignoreGhsas:\s*(#.*)?$/;
const ENTRY = /^\s+-\s+(?<id>GHSA(?:-[0-9a-z]{4}){3})(?:\s+#(?<comment>.*))?$/;
const POLICY = /^\s*revisar:\s*(?<date>\S+)\s*\|\s*motivo:\s*\S/;

const isIgnorable = (line) => line.trim() === "" || line.trim().startsWith("#");

function isCalendarDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().startsWith(value);
}

function entryViolation({ id, comment }, today) {
  const date = comment?.match(POLICY)?.groups.date;
  if (!date) return `${id}: falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea`;
  if (!isCalendarDate(date)) return `${id}: fecha de revisión inválida '${date}'`;
  return date < today ? `${id}: fecha de revisión vencida (${date})` : null;
}

/**
 * @param {string} workspaceYaml content of pnpm-workspace.yaml
 * @param {string} today AAAA-MM-DD
 * @returns {string[]} one message per violation; empty when the file complies
 */
export function auditIgnoreViolations(workspaceYaml, today) {
  const lines = workspaceYaml.split(/\r?\n/);
  const start = lines.findIndex((line) => BLOCK_START.test(line));
  if (start === -1) return [];

  const unrecognized = (line) => `línea no reconocida en auditConfig: '${line}'`;
  const { inline } = lines[start].match(BLOCK_START).groups;
  const violations = isIgnorable(inline) ? [] : [unrecognized(lines[start])];

  let inList = false;
  for (const line of lines.slice(start + 1)) {
    if (isIgnorable(line)) continue;
    if (!/^\s/.test(line)) break;

    const entry = inList ? line.match(ENTRY)?.groups : undefined;
    if (entry) {
      const violation = entryViolation(entry, today);
      if (violation) violations.push(violation);
    } else if (LIST_KEY.test(line)) {
      inList = true;
    } else {
      violations.push(unrecognized(line));
    }
  }
  return violations;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [file] = process.argv.slice(2);
  if (!file) {
    console.error("uso: audit-ignores.mjs <pnpm-workspace.yaml>");
    process.exit(2);
  }
  const today = new Date().toISOString().slice(0, 10);
  const violations = auditIgnoreViolations(readFileSync(file, "utf8"), today);
  for (const violation of violations) console.error(violation);
  process.exit(violations.length === 0 ? 0 : 1);
}
