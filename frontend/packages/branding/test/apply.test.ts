import { afterEach, describe, expect, it } from "vitest";
import { applyBranding, BRAND_VARS, clearBranding, readSurfaces } from "../src/apply";

afterEach(() => document.documentElement.removeAttribute("style"));

describe("applyBranding / clearBranding", () => {
  it("escribe las variables recibidas", () => {
    applyBranding(document.documentElement, { "--brand-primary": "#8B2F5C" });

    expect(document.documentElement.style.getPropertyValue("--brand-primary")).toBe("#8B2F5C");
  });

  it("clearBranding quita todas las claves gestionadas y respeta las ajenas", () => {
    const root = document.documentElement;
    root.style.setProperty("--sidebar-width", "20rem");
    applyBranding(root, Object.fromEntries(BRAND_VARS.map((key) => [key, "x"])));

    clearBranding(root);

    for (const key of BRAND_VARS) expect(root.style.getPropertyValue(key)).toBe("");
    expect(root.style.getPropertyValue("--sidebar-width")).toBe("20rem");
  });

  it("aplicar de nuevo quita lo que la marca anterior escribió y la nueva no", () => {
    const root = document.documentElement;
    applyBranding(root, { "--brand-primary": "#8B2F5C", "--ring": "var(--palette-canopy-500)" });

    applyBranding(root, { "--brand-primary": "#1D6C4E" });

    expect(root.style.getPropertyValue("--ring")).toBe("");
    expect(root.style.getPropertyValue("--brand-primary")).toBe("#1D6C4E");
  });

  it("adversarial: ignora claves que no gestiona (no escribe estilos arbitrarios)", () => {
    applyBranding(document.documentElement, { "--background": "#000000", color: "red" });

    expect(document.documentElement.style.getPropertyValue("--background")).toBe("");
    expect(document.documentElement.style.color).toBe("");
  });
});

describe("readSurfaces", () => {
  it("lee --background y --sidebar resueltos", () => {
    const root = document.documentElement;
    root.style.setProperty("--background", "#ffffff");
    root.style.setProperty("--sidebar", "#e0e8e2");

    expect(readSurfaces(root)).toEqual({ background: "#ffffff", sidebar: "#e0e8e2" });
  });

  it("si --sidebar no existe usa #F2F4EF", () => {
    document.documentElement.style.setProperty("--background", "#ffffff");

    expect(readSurfaces(document.documentElement).sidebar).toBe("#F2F4EF");
  });

  it("adversarial: un valor ilegible cae al respaldo en vez de romper el contraste", () => {
    document.documentElement.style.setProperty("--background", "transparent");

    expect(readSurfaces(document.documentElement).background).toBe("#FFFFFF");
  });
});
