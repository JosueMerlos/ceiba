import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { auditIgnoreViolations, parseIgnoredAdvisories } from "../audit-ignores.mjs";

const TODAY = "2026-11-18";
const ID = "GHSA-fc5q-39xc-vjpf";
const OTHER_ID = "GHSA-aaaa-bbbb-cccc";
const MISSING_POLICY = "falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea";

const workspace = (...entries: string[]) => `packages:
  - apps/*
audit:
  ignore:
${entries.map((entry) => `    - ${entry}`).join("\n")}
`;
const violations = (yaml: string, ignored = [ID]) => auditIgnoreViolations(yaml, ignored, TODAY);

describe("auditIgnoreViolations", () => {
  it("acepta que pnpm no ignore ningún aviso", () => {
    expect(violations("packages:\n  - apps/*\n", [])).toEqual([]);
  });

  it("acepta un aviso con motivo y fecha futura", () => {
    expect(violations(workspace(`${ID} # revisar: 2026-12-18 | motivo: solo tooling`))).toEqual([]);
  });

  it("acepta un aviso cuya revisión vence hoy", () => {
    expect(violations(workspace(`${ID} # revisar: ${TODAY} | motivo: solo tooling`))).toEqual([]);
  });

  it("acepta un aviso entre comillas", () => {
    expect(violations(workspace(`"${ID}" # revisar: 2026-12-18 | motivo: solo tooling`))).toEqual(
      [],
    );
  });

  it("rechaza una fecha vencida y nombra el aviso", () => {
    expect(violations(workspace(`${ID} # revisar: 2026-11-17 | motivo: solo tooling`))).toEqual([
      `${ID}: fecha de revisión vencida (2026-11-17)`,
    ]);
  });

  it.each(["2026-02-31", "2026-13-01", "18-12-2026", "pronto"])(
    "rechaza la fecha inválida %s",
    (date) => {
      expect(violations(workspace(`${ID} # revisar: ${date} | motivo: solo tooling`))).toEqual([
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
    expect(violations(workspace(entry))).toEqual([`${ID}: ${MISSING_POLICY}`]);
  });

  // The list comes from pnpm's effective config, so the source of an ignore does not matter:
  // without its own annotated line it fails.
  it.each([
    ["que no aparece en el archivo (variable de entorno o config global)", "packages:\n  - a\n"],
    ["en una lista en línea", `audit: { ignore: [${ID}] }\n`],
    ["anotado solo en un comentario", `# - ${ID} # revisar: 2026-12-18 | motivo: solo tooling\n`],
    [
      "citado solo en el motivo de otro",
      workspace(`${OTHER_ID} # revisar: 2026-12-18 | motivo: ver ${ID}`),
    ],
  ])("rechaza un aviso %s", (_case, yaml) => {
    expect(violations(yaml)).toEqual([`${ID}: ${MISSING_POLICY}`]);
  });

  it("acepta saltos de línea CRLF y CR", () => {
    const yaml = workspace(`${ID} # revisar: 2026-12-18 | motivo: solo tooling`);

    expect(violations(yaml.replaceAll("\n", "\r\n"))).toEqual([]);
    expect(violations(yaml.replaceAll("\n", "\r"))).toEqual([]);
  });

  it("reporta cada aviso inválido y deja pasar los válidos", () => {
    const yaml = workspace(
      `${OTHER_ID} # revisar: 2026-12-18 | motivo: solo tooling`,
      "GHSA-dddd-eeee-ffff # revisar: 2026-01-01 | motivo: solo tooling",
      "GHSA-gggg-hhhh-jjjj",
    );

    expect(violations(yaml, [OTHER_ID, "GHSA-dddd-eeee-ffff", "GHSA-gggg-hhhh-jjjj"])).toEqual([
      "GHSA-dddd-eeee-ffff: fecha de revisión vencida (2026-01-01)",
      `GHSA-gggg-hhhh-jjjj: ${MISSING_POLICY}`,
    ]);
  });
});

describe("parseIgnoredAdvisories", () => {
  it("lee la lista de la configuración efectiva", () => {
    expect(parseIgnoredAdvisories(JSON.stringify({ ignore: [ID] }))).toEqual([ID]);
  });

  it("interpreta null como ningún aviso ignorado", () => {
    expect(parseIgnoredAdvisories("null\n")).toEqual([]);
  });

  it("interpreta una configuración sin ignore como ningún aviso ignorado", () => {
    expect(parseIgnoredAdvisories("{}")).toEqual([]);
  });

  // An unreadable config must stop the check, never read as "nothing ignored".
  it.each(["", "undefined", "[]", '"x"', '{"ignore":"GHSA"}', '{"ignore":[1]}'])(
    "rechaza la salida inesperada %j",
    (output) => {
      expect(() => parseIgnoredAdvisories(output)).toThrow();
    },
  );
});

describe("audit-ignores.mjs por línea de comandos", () => {
  const dirs: string[] = [];
  afterEach(() => dirs.splice(0).forEach((dir) => rmSync(dir, { recursive: true, force: true })));

  // The directory name needs URL encoding: the check must still run from such a checkout.
  function run(yaml: string, stdin: string) {
    const dir = mkdtempSync(join(tmpdir(), "audit ñ-"));
    dirs.push(dir);
    const script = join(dir, "audit-ignores.mjs");
    copyFileSync(new URL("../audit-ignores.mjs", import.meta.url), script);
    writeFileSync(join(dir, "pnpm-workspace.yaml"), yaml);
    return spawnSync(process.execPath, [script, join(dir, "pnpm-workspace.yaml")], {
      input: stdin,
      encoding: "utf8",
    });
  }
  const effective = JSON.stringify({ ignore: [ID] });

  it("termina en 0 si el aviso cumple la política", () => {
    const result = run(workspace(`${ID} # revisar: 2999-01-01 | motivo: solo tooling`), effective);

    expect(result.status).toBe(0);
  });

  it("termina en 1 y explica la violación", () => {
    const result = run(workspace(ID), effective);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(`${ID}: ${MISSING_POLICY}`);
  });

  it("no termina en 0 si no recibe la configuración de pnpm", () => {
    const result = run(workspace(ID), "");

    expect(result.status).not.toBe(0);
    expect(result.status).not.toBeNull();
  });
});
