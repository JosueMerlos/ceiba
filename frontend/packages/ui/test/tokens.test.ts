import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// Modelo de tres capas (ADR-0031): primitivo (--palette-*) -> semántico (nombres de shadcn/ui, con --brand-* como
// capa de marca que M2.04 sobrescribe por empresa) -> componente (--button-*, --input-*...).
const css = readFileSync(join(import.meta.dirname, "../src/styles/tokens.css"), "utf8");

const declarations = new Map<string, string>();
for (const match of css.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)) {
  declarations.set(match[1]!, match[2]!.trim().replace(/\s+/g, " "));
}

/** Sigue las cadenas var(--x) hasta un valor final (#hex). */
function resolve(name: string): string {
  let value = declarations.get(name);
  if (value === undefined) throw new Error(`token ${name} no definido`);
  for (let guard = 0; guard < 10; guard += 1) {
    const reference = /^var\((--[\w-]+)\)$/.exec(value);
    if (!reference) return value;
    value = declarations.get(reference[1]!);
    if (value === undefined) throw new Error(`token ${reference[1]} no definido`);
  }
  throw new Error(`ciclo en ${name}`);
}

function luminance(hex: string): number {
  const channels = [1, 3, 5].map((start) => {
    const value = parseInt(hex.slice(start, start + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * channels[0]! + 0.7152 * channels[1]! + 0.0722 * channels[2]!;
}

function contrast(foreground: string, background: string): number {
  const [light, dark] = [luminance(resolve(foreground)), luminance(resolve(background))].sort(
    (a, b) => b - a,
  ) as [number, number];
  return (light + 0.05) / (dark + 0.05);
}

describe("capa de marca: --brand-*", () => {
  const brand = [
    "--brand-primary",
    "--brand-primary-foreground",
    "--brand-secondary",
    "--brand-secondary-foreground",
    "--brand-accent",
    "--brand-accent-foreground",
    "--brand-font",
  ];

  it("define un valor por defecto para cada variable de marca (ADR-0025)", () => {
    for (const name of brand) expect(declarations.has(name), name).toBe(true);
  });

  it("los defaults de marca salen de la paleta primitiva, sin valores sueltos", () => {
    for (const name of brand.filter((item) => item !== "--brand-font")) {
      expect(declarations.get(name), name).toMatch(/^var\(--palette-[\w-]+\)$/);
    }
  });
});

describe("capa semántica: nombres de shadcn/ui", () => {
  const semantic = [
    "--background",
    "--foreground",
    "--card",
    "--card-foreground",
    "--popover",
    "--popover-foreground",
    "--primary",
    "--primary-foreground",
    "--secondary",
    "--secondary-foreground",
    "--muted",
    "--muted-foreground",
    "--accent",
    "--accent-foreground",
    "--destructive",
    "--destructive-foreground",
    "--border",
    "--input",
    "--ring",
    "--radius",
  ];

  it("conserva todos los nombres de shadcn/ui", () => {
    for (const name of semantic) expect(declarations.has(name), name).toBe(true);
  });

  it("--primary y --secondary leen de la capa de marca (así M2.04 cambia el tema sin tocar componentes)", () => {
    expect(declarations.get("--primary")).toBe("var(--brand-primary)");
    expect(declarations.get("--primary-foreground")).toBe("var(--brand-primary-foreground)");
    expect(declarations.get("--secondary")).toBe("var(--brand-secondary)");
    expect(declarations.get("--secondary-foreground")).toBe("var(--brand-secondary-foreground)");
  });

  it("expone el acento de marca como --highlight (--accent conserva el rol de shadcn: superficie al pasar el cursor)", () => {
    expect(declarations.get("--highlight")).toBe("var(--brand-accent)");
    expect(declarations.get("--highlight-foreground")).toBe("var(--brand-accent-foreground)");
  });
});

describe("capa de componente", () => {
  it("los tokens de componente solo referencian la capa semántica", () => {
    const component = [...declarations].filter(([name]) =>
      /^--(button|input|dialog|nav|sidebar)-/.test(name),
    );

    expect(component.length).toBeGreaterThan(5);
    for (const [name, value] of component) {
      expect(value, name).not.toMatch(/--palette-|--brand-|#[0-9a-f]{3,8}/i);
    }
  });
});

describe("contraste WCAG AA (4.5:1) de los pares por defecto", () => {
  const pairs: [string, string][] = [
    ["--foreground", "--background"],
    ["--card-foreground", "--card"],
    ["--popover-foreground", "--popover"],
    ["--primary-foreground", "--primary"],
    ["--secondary-foreground", "--secondary"],
    ["--muted-foreground", "--muted"],
    ["--muted-foreground", "--background"],
    ["--highlight-foreground", "--highlight"],
    ["--destructive-foreground", "--destructive"],
  ];

  it.each(pairs)("%s sobre %s", (foreground, background) => {
    expect(contrast(foreground, background)).toBeGreaterThanOrEqual(4.5);
  });
});

// WCAG 1.4.11: los componentes de interfaz y sus estados necesitan 3:1 contra el fondo contiguo.
describe("contraste no textual (3:1)", () => {
  const pairs: [string, string][] = [
    ["--input", "--card"],
    ["--input", "--background"],
    ["--ring", "--background"],
    ["--ring", "--card"],
    ["--nav-item-active-indicator", "--card"],
  ];

  it.each(pairs)("%s sobre %s", (foreground, background) => {
    expect(contrast(foreground, background)).toBeGreaterThanOrEqual(3);
  });
});

describe("marca re-alcanzable en un contenedor (ADR-0031, vista previa de M2.04)", () => {
  it("la capa semántica se declara en :root Y en [data-brand-scope]", () => {
    expect(css).toMatch(/:root,\s*\[data-brand-scope\]\s*\{[^}]*--primary:/s);
  });

  it("--ring sigue a la marca", () => {
    expect(declarations.get("--ring")).toBe("var(--brand-primary)");
  });
});
