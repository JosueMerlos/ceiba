import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { IMPORT_KINDS } from "./kinds";

// The downloadable templates must name exactly the columns the backend importers read: a template that drifts would
// produce files that fail on upload. The contract lists them (`x-template-columns`, generated from the importers, and
// kept in sync by the api-contract check), so the test reads the contract instead of the Ruby sources.
const contract = readFileSync(
  resolve(__dirname, "../../../../../../backend/openapi/v1.yaml"),
  "utf8",
);

const importerColumns = (kind: string) => {
  const block = /x-template-columns:\n((?: {8}.*\n)+)/.exec(contract)?.[1] ?? "";
  const section = new RegExp(`^ {8}${kind}:\\n((?: {8}- .*\\n)+)`, "m").exec(block)?.[1] ?? "";
  return [...section.matchAll(/- (\S+)/g)].map((match) => match[1]);
};

const templateHeader = (file: string) =>
  readFileSync(resolve(__dirname, "../../../public/import-templates", file), "utf8")
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)[0]!
    .split(";");

describe("plantillas de importación", () => {
  it.each(IMPORT_KINDS.map((kind) => [kind.key, kind.template] as const))(
    "la plantilla de %s trae las columnas de su importador",
    (key, template) => {
      expect(templateHeader(template)).toEqual(importerColumns(key));
    },
  );

  it("cada plantilla empieza con BOM para que Excel la abra como UTF-8", () => {
    for (const kind of IMPORT_KINDS) {
      expect(
        readFileSync(
          resolve(__dirname, "../../../public/import-templates", kind.template),
          "utf8",
        ).startsWith("\uFEFF"),
      ).toBe(true);
    }
  });
});
