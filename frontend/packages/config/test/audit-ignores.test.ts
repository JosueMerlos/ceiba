import { describe, expect, it } from "vitest";
import { auditIgnoreViolations } from "../audit-ignores.mjs";

const TODAY = "2026-11-18";
const ID = "GHSA-fc5q-39xc-vjpf";

const workspace = (auditConfig: string) => `packages:
  - apps/*
${auditConfig}
minimumReleaseAgeExclude:
  - i18next@27.1.0
`;
const withEntry = (entry: string) => workspace(`auditConfig:\n  ignoreGhsas:\n    - ${entry}`);
const violations = (yaml: string) => auditIgnoreViolations(yaml, TODAY);

describe("auditIgnoreViolations", () => {
  it("acepta un archivo sin auditConfig", () => {
    expect(violations("packages:\n  - apps/*\n")).toEqual([]);
  });

  it("acepta un aviso con motivo y fecha futura", () => {
    expect(violations(withEntry(`${ID} # revisar: 2026-12-18 | motivo: solo tooling`))).toEqual([]);
  });

  it("acepta un aviso cuya revisión vence hoy", () => {
    expect(violations(withEntry(`${ID} # revisar: ${TODAY} | motivo: solo tooling`))).toEqual([]);
  });

  it("rechaza una fecha vencida y nombra el aviso", () => {
    expect(violations(withEntry(`${ID} # revisar: 2026-11-17 | motivo: solo tooling`))).toEqual([
      `${ID}: fecha de revisión vencida (2026-11-17)`,
    ]);
  });

  it.each(["2026-02-31", "2026-13-01", "18-12-2026", "pronto"])(
    "rechaza la fecha inválida %s",
    (date) => {
      expect(violations(withEntry(`${ID} # revisar: ${date} | motivo: solo tooling`))).toEqual([
        `${ID}: fecha de revisión inválida '${date}'`,
      ]);
    },
  );

  it.each([
    ["sin comentario", ID],
    ["sin motivo", `${ID} # revisar: 2026-12-18`],
    ["con motivo vacío", `${ID} # revisar: 2026-12-18 | motivo:   `],
    ["sin fecha", `${ID} # motivo: solo tooling`],
  ])("rechaza un aviso %s", (_case, entry) => {
    expect(violations(withEntry(entry))).toEqual([
      `${ID}: falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea`,
    ]);
  });

  it("reporta cada aviso inválido y deja pasar los válidos", () => {
    const yaml = workspace(`auditConfig:
  ignoreGhsas:
    - GHSA-aaaa-bbbb-cccc # revisar: 2026-12-18 | motivo: solo tooling
    - GHSA-dddd-eeee-ffff # revisar: 2026-01-01 | motivo: solo tooling
    - GHSA-gggg-hhhh-jjjj`);

    expect(violations(yaml)).toEqual([
      "GHSA-dddd-eeee-ffff: fecha de revisión vencida (2026-01-01)",
      "GHSA-gggg-hhhh-jjjj: falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea",
    ]);
  });

  it("ignora los comentarios y las líneas en blanco dentro del bloque", () => {
    const yaml = workspace(`auditConfig:
  # why this block exists
  ignoreGhsas:

    # picomatch
    - ${ID} # revisar: 2026-12-18 | motivo: solo tooling`);

    expect(violations(yaml)).toEqual([]);
  });

  // Whatever the checker cannot read must fail: otherwise pnpm would honor an ignore nobody validated.
  it.each([
    [
      "una lista en línea",
      "auditConfig:\n  ignoreGhsas: [GHSA-aaaa-bbbb-cccc]",
      "  ignoreGhsas: [GHSA-aaaa-bbbb-cccc]",
    ],
    [
      "un auditConfig en línea",
      "auditConfig: { ignoreGhsas: [GHSA-aaaa-bbbb-cccc] }",
      "auditConfig: { ignoreGhsas: [GHSA-aaaa-bbbb-cccc] }",
    ],
    ["ignoreCves", "auditConfig:\n  ignoreCves:\n    - CVE-2026-1", "  ignoreCves:"],
  ])("rechaza %s", (_case, block, line) => {
    expect(violations(workspace(block))).toContain(`línea no reconocida en auditConfig: '${line}'`);
  });

  it("rechaza un identificador que no es un GHSA", () => {
    expect(
      violations(withEntry("CVE-2026-1 # revisar: 2026-12-18 | motivo: solo tooling")),
    ).toEqual([
      "línea no reconocida en auditConfig: '    - CVE-2026-1 # revisar: 2026-12-18 | motivo: solo tooling'",
    ]);
  });
});
