import { describe, expect, it } from "vitest";
import { contrastRatio } from "../src/contrast";
import { analyzeBranding, DARK_FOREGROUND_HEX, resolveBrandVars } from "../src/resolve";

const SURFACES = { background: "#FFFFFF", sidebar: "#F2F4EF" };
const NONE = { primaryColor: null, secondaryColor: null, accentColor: null, fontChoice: null };

describe("resolveBrandVars", () => {
  it("criterio 1: #FFFF00 elige texto oscuro con contraste >= 4.5", () => {
    const vars = resolveBrandVars({ ...NONE, primaryColor: "#FFFF00" }, SURFACES);

    expect(vars["--brand-primary"]).toBe("#FFFF00");
    expect(vars["--brand-primary-foreground"]).toBe("var(--palette-kapok-900)");
    expect(contrastRatio("#FFFF00", DARK_FOREGROUND_HEX)).toBeGreaterThanOrEqual(4.5);
  });

  it("#FFFF00 cae el anillo de foco a canopy-500 (1.07:1 contra blanco)", () => {
    const vars = resolveBrandVars({ ...NONE, primaryColor: "#FFFF00" }, SURFACES);

    expect(vars["--ring"]).toBe("var(--palette-canopy-500)");
    expect(vars["--sidebar-ring"]).toBe("var(--palette-canopy-500)");
  });

  it("#1D6C4E usa texto blanco y conserva el anillo de la marca", () => {
    const vars = resolveBrandVars({ ...NONE, primaryColor: "#1D6C4E" }, SURFACES);

    expect(vars["--brand-primary-foreground"]).toBe("var(--palette-kapok-0)");
    expect(vars).not.toHaveProperty("--ring");
    expect(vars).not.toHaveProperty("--sidebar-ring");
  });

  it("adversarial: un primario que pasa 3:1 contra blanco pero no contra el sidebar hace caer el anillo", () => {
    const primary = "#8F9690";
    expect(contrastRatio(primary, "#FFFFFF")).toBeGreaterThanOrEqual(3);
    expect(contrastRatio(primary, "#F2F4EF")).toBeLessThan(3);

    const vars = resolveBrandVars({ ...NONE, primaryColor: primary }, SURFACES);

    expect(vars["--ring"]).toBe("var(--palette-canopy-500)");
  });

  it("todo nulo no emite nada: queda la paleta de la plataforma", () => {
    expect(resolveBrandVars(NONE, SURFACES)).toEqual({});
  });

  it("sin fuente elegida no emite --brand-font; con una elegida emite su familia", () => {
    expect(resolveBrandVars({ ...NONE, primaryColor: "#1D6C4E" }, SURFACES)).not.toHaveProperty(
      "--brand-font",
    );
    expect(resolveBrandVars({ ...NONE, fontChoice: "lora" }, SURFACES)["--brand-font"]).toContain(
      "Lora Variable",
    );
  });

  it("un color nulo no emite su par, aunque otros sí", () => {
    const vars = resolveBrandVars({ ...NONE, accentColor: "#C8873A" }, SURFACES);

    expect(Object.keys(vars).sort()).toEqual(["--brand-accent", "--brand-accent-foreground"]);
  });

  it("si ningún texto llega a 4.5 se omite el par completo (hereda el de la plataforma)", () => {
    // Mid-gray: below 4.5 against both white and the dark text.
    const vars = resolveBrandVars({ ...NONE, secondaryColor: "#6B7C8C" }, SURFACES);

    expect(vars).not.toHaveProperty("--brand-secondary");
    expect(vars).not.toHaveProperty("--brand-secondary-foreground");
  });

  it("adversarial: un hex mal formado se ignora en vez de escribirse en el CSS", () => {
    const vars = resolveBrandVars(
      { ...NONE, primaryColor: "red; background:url(x)", accentColor: "#12" },
      SURFACES,
    );

    expect(vars).toEqual({});
  });
});

describe("analyzeBranding", () => {
  it("avisa del texto corregido y del anillo cuando el primario es claro", () => {
    const { notices } = analyzeBranding({ ...NONE, primaryColor: "#FFFF00" }, SURFACES);

    expect(notices.darkText).toEqual(["primary"]);
    expect(notices.ringFallback).toBe(true);
  });

  it("no avisa cuando la marca ya cumple", () => {
    const { notices } = analyzeBranding({ ...NONE, primaryColor: "#1D6C4E" }, SURFACES);

    expect(notices).toEqual({ darkText: [], ringFallback: false, unreadable: [] });
  });

  it("adversarial: avisa cuando un tono medio no admite texto legible y se descarta (#777777)", () => {
    const { vars, notices } = analyzeBranding({ ...NONE, primaryColor: "#777777" }, SURFACES);

    expect(vars["--brand-primary"]).toBeUndefined();
    expect(notices.unreadable).toEqual(["primary"]);
    expect(notices.darkText).toEqual([]);
  });
});
