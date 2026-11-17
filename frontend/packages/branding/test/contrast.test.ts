import { describe, expect, it } from "vitest";
import { contrastRatio, relativeLuminance } from "../src/contrast";

describe("relativeLuminance", () => {
  it("es 1 para el blanco y 0 para el negro", () => {
    expect(relativeLuminance("#FFFFFF")).toBeCloseTo(1, 5);
    expect(relativeLuminance("#000000")).toBeCloseTo(0, 5);
  });

  it("linealiza con el umbral 0.04045 (un canal justo bajo y sobre el umbral)", () => {
    // 0x0A = 10/255 = 0.0392 (< 0.04045, rama lineal); 0x0B = 0.0431 (rama exponencial).
    expect(relativeLuminance("#0A0000")).toBeCloseTo(0.2126 * (0.0392157 / 12.92), 6);
    expect(relativeLuminance("#0B0000")).toBeCloseTo(0.2126 * ((0.0431373 + 0.055) / 1.055) ** 2.4, 6);
  });
});

describe("contrastRatio", () => {
  it("blanco contra negro es 21:1", () => {
    expect(contrastRatio("#FFFFFF", "#000000")).toBeCloseTo(21, 5);
  });

  it("colores idénticos dan 1:1", () => {
    expect(contrastRatio("#1D6C4E", "#1D6C4E")).toBeCloseTo(1, 5);
  });

  it("#777777 contra blanco queda justo bajo AA (≈ 4.48)", () => {
    const ratio = contrastRatio("#777777", "#FFFFFF");
    expect(ratio).toBeGreaterThan(4.47);
    expect(ratio).toBeLessThan(4.5);
  });

  it("es simétrico", () => {
    expect(contrastRatio("#1D6C4E", "#F2F4EF")).toBeCloseTo(contrastRatio("#F2F4EF", "#1D6C4E"), 10);
  });

  it("ignora mayúsculas y minúsculas", () => {
    expect(contrastRatio("#1d6c4e", "#ffffff")).toBeCloseTo(contrastRatio("#1D6C4E", "#FFFFFF"), 10);
  });

  it("adversarial: un valor que no es #RRGGBB lanza en vez de devolver un número engañoso", () => {
    expect(() => contrastRatio("verde", "#FFFFFF")).toThrow(/#RRGGBB/);
    expect(() => contrastRatio("#FFF", "#FFFFFF")).toThrow(/#RRGGBB/);
  });
});
