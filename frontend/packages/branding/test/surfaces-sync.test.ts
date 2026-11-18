import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { readSurfaces } from "../src/apply";
import { contrastRatio } from "../src/contrast";
import { resolveBrandVars } from "../src/resolve";

// Vitest runs from the package directory; jsdom replaces URL, so import.meta.url cannot be used here.
const tokens = readFileSync(resolve(process.cwd(), "../ui/src/styles/tokens.css"), "utf8");

// Follows `var(--x)` references through the token file until a literal value is reached.
function resolveToken(name: string, seen = new Set<string>()): string {
  if (seen.has(name)) throw new Error(`circular token ${name}`);
  const match = tokens.match(new RegExp(`${name}:\\s*([^;]+);`));
  if (!match) throw new Error(`token ${name} not found`);
  const value = match[1]!.trim();
  const reference = value.match(/^var\((--[\w-]+)\)$/);
  return reference ? resolveToken(reference[1]!, new Set(seen).add(name)) : value;
}

const NO_BRAND = { primaryColor: null, secondaryColor: null, accentColor: null, fontChoice: null };

describe("superficies del marco y hoja frente a las que lee @ceiba/branding", () => {
  // Without the stylesheet (jsdom) readSurfaces returns its fallbacks: they must be what the tokens resolve to,
  // or a token change would make the contrast check run against a surface nobody sees.
  const fallbacks = readSurfaces(document.createElement("div"));

  it("--background resuelve al fallback de la hoja", () => {
    expect(resolveToken("--background").toUpperCase()).toBe(fallbacks.background.toUpperCase());
  });

  it("--sidebar resuelve al fallback del sidebar", () => {
    expect(resolveToken("--sidebar").toUpperCase()).toBe(fallbacks.sidebar.toUpperCase());
  });

  it("--sidebar-ring es un token real y sigue a la marca", () => {
    expect(tokens).toMatch(/--sidebar-ring:\s*var\(--brand-primary\);/);
  });

  it("el verde de respaldo del anillo (canopy-500) da >= 3:1 contra ambas superficies", () => {
    const ring = resolveToken("--palette-canopy-500");
    expect(contrastRatio(ring, resolveToken("--background"))).toBeGreaterThanOrEqual(3);
    expect(contrastRatio(ring, resolveToken("--sidebar"))).toBeGreaterThanOrEqual(3);
  });

  it("#FFFF00 con las superficies reales: texto oscuro y anillo de respaldo en --ring y --sidebar-ring", () => {
    const vars = resolveBrandVars({ ...NO_BRAND, primaryColor: "#FFFF00" }, fallbacks);

    expect(vars["--brand-primary-foreground"]).toBe("var(--palette-kapok-900)");
    expect(vars["--ring"]).toBe("var(--palette-canopy-500)");
    expect(vars["--sidebar-ring"]).toBe("var(--palette-canopy-500)");
  });
});
