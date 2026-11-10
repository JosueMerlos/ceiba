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
  describe("textos de la UI (i18n)", () => {
    it("prohíbe texto literal en el JSX de las apps", async () => {
      const code = `export function Hello() {\n  return <p>Hola mundo</p>;\n}\n`;

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it("prohíbe texto literal en atributos de la UI (placeholder, aria-label, title)", async () => {
      const code = `export function Hello() {\n  return <input placeholder="Correo" aria-label="Correo electrónico" />;\n}\n`;

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it("acepta textos que vienen de t()", async () => {
      const code = `export function Hello({ t }: { t: (key: string) => string }) {\n  return <p>{t("hola")}</p>;\n}\n`;

      expect(await lint(code)).toEqual([]);
    });

    it("acepta nombres de clase, tipos de input y roles (no son texto de UI)", async () => {
      const code = `export function Hello() {\n  return <input type="email" className="a b" role="search" />;\n}\n`;

      expect(await lint(code)).toEqual([]);
    });

    it("prohíbe template literals como texto del JSX", async () => {
      const code = "export function Hello() {\n  return <p>{`Hola mundo`}</p>;\n}\n";

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it("prohíbe string literal en una expresión del JSX", async () => {
      const code = `export function Hello() {\n  return <p>{"Hola mundo"}</p>;\n}\n`;

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it.each([
      "description",
      "skipLinkLabel",
      "navigationLabel",
      "triggerLabel",
      "summary",
      "closeLabel",
      "fallback",
      "title",
    ])("prohíbe texto literal en la prop de UI %s", async (prop) => {
      const code = `export const View = () => <Widget ${prop}="Texto visible" />;\n`;

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it("prohíbe template literals en atributos de texto", async () => {
      const code = "export const View = () => <Widget description={`Texto visible`} />;\n";

      expect(await lint(code)).toContain("i18next/no-literal-string");
    });

    it.each(["error", "success", "warning", "info", "message"])(
      "prohíbe toast.%s con texto literal",
      async (method) => {
        const code = `import { toast } from "x";\nexport const run = () => toast.${method}("Texto visible");\n`;

        expect(await lint(code, "apps/panel/src/example.ts")).toContain("no-restricted-syntax");
      },
    );

    it("prohíbe toast() con un template literal", async () => {
      const code = 'import { toast } from "x";\nexport const run = () => toast(`Texto visible`);\n';

      expect(await lint(code, "apps/panel/src/example.ts")).toContain("no-restricted-syntax");
    });

    it("acepta toast con un texto que viene de t()", async () => {
      const code = `import { toast } from "x";\nexport const run = (t: (k: string) => string) => toast.error(t("errors:generic"));\n`;

      expect(await lint(code, "apps/panel/src/example.ts")).toEqual([]);
    });

    it("no se aplica a los tests", async () => {
      const code = `export const View = () => <p>Hola mundo</p>;\n`;

      expect(await lint(code, "apps/panel/src/example.test.tsx")).toEqual([]);
    });
  });
});
