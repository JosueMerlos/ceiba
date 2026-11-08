import { format } from "prettier";
import { describe, expect, it } from "vitest";
import config from "../prettier.mjs";

describe("configuración compartida de Prettier", () => {
  it("formatea con comillas dobles, punto y coma y coma final", async () => {
    const output = await format("const a = {b: 'x'}", { ...config, parser: "typescript" });

    expect(output).toBe('const a = { b: "x" };\n');
  });

  it("parte las líneas a 100 columnas", () => {
    expect(config.printWidth).toBe(100);
  });
});
