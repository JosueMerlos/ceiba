import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const base = JSON.parse(readFileSync(new URL("../tsconfig.base.json", import.meta.url), "utf8"));

describe("tsconfig base", () => {
  it.each([
    "strict",
    "noUncheckedIndexedAccess",
    "noImplicitOverride",
    "noUnusedLocals",
    "noUnusedParameters",
    "verbatimModuleSyntax",
  ])("activa %s", (flag) => {
    expect(base.compilerOptions[flag]).toBe(true);
  });

  it("no emite archivos (los builds los hace Vite)", () => {
    expect(base.compilerOptions.noEmit).toBe(true);
  });
});
