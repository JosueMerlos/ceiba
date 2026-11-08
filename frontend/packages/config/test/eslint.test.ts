import { ESLint } from "eslint";
import { describe, expect, it } from "vitest";
import config from "../eslint.mjs";

// Lint de código en memoria con la configuración compartida, como si fuera un archivo de una app.
const lint = async (code: string, filePath = "apps/panel/src/example.tsx") => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: config,
    cwd: import.meta.dirname,
  });
  const [result] = await eslint.lintText(code, { filePath: `${import.meta.dirname}/${filePath}` });
  return result?.messages.map((message) => message.ruleId) ?? [];
};

describe("configuración compartida de ESLint", () => {
  it("acepta código TypeScript/React correcto", async () => {
    const code = `export function Hello({ name }: { name: string }) {\n  return <p>{name}</p>;\n}\n`;

    expect(await lint(code)).toEqual([]);
  });

  it("prohíbe any explícito", async () => {
    expect(await lint("export const value: any = 1;\n", "src/a.ts")).toContain(
      "@typescript-eslint/no-explicit-any",
    );
  });

  it("detecta variables sin usar", async () => {
    expect(await lint("const unused = 1;\nexport {};\n", "src/a.ts")).toContain(
      "@typescript-eslint/no-unused-vars",
    );
  });

  it("exige imports de solo tipos con `import type`", async () => {
    const code = `import { ReactNode } from "react";\nexport const node: ReactNode = null;\n`;

    expect(await lint(code, "src/a.tsx")).toContain("@typescript-eslint/consistent-type-imports");
  });

  it("aplica las reglas de hooks de React", async () => {
    const code = `import { useState } from "react";\nexport function Bad({ on }: { on: boolean }) {\n  if (on) useState(0);\n  return null;\n}\n`;

    expect(await lint(code)).toContain("react-hooks/rules-of-hooks");
  });

  it("prohíbe console.log salvo warn y error", async () => {
    expect(await lint('console.log("x");\n', "src/a.ts")).toContain("no-console");
    expect(await lint('console.error("x");\n', "src/a.ts")).not.toContain("no-console");
  });
});
