import { describe, expect, it } from "vitest";
import { loadBrandFont } from "../../src/react/fonts";

describe("loadBrandFont", () => {
  it("Figtree es la tipografía de la plataforma: no hay nada que cargar", async () => {
    await expect(loadBrandFont("figtree")).resolves.toBeUndefined();
  });

  it("carga la tipografía elegida bajo demanda", async () => {
    await expect(loadBrandFont("lora")).resolves.toBeUndefined();
    await expect(loadBrandFont("nunito")).resolves.toBeUndefined();
  });

  it("pedir la misma tipografía dos veces comparte una sola carga", () => {
    expect(loadBrandFont("lora")).toBe(loadBrandFont("lora"));
  });
});
