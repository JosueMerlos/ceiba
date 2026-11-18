import { describe, expect, it } from "vitest";
import { minorToInput, parsePriceToMinor } from "./money";

describe("parsePriceToMinor", () => {
  it("convierte unidades mayores a unidades menores", () => {
    expect(parsePriceToMinor("250")).toBe(25000);
    expect(parsePriceToMinor("250.5")).toBe(25050);
    expect(parsePriceToMinor("0.07")).toBe(7);
  });

  it("acepta la coma decimal y los espacios alrededor", () => {
    expect(parsePriceToMinor(" 12,34 ")).toBe(1234);
  });

  it("no pierde un centavo por punto flotante (19.99 y 1.15)", () => {
    expect(parsePriceToMinor("19.99")).toBe(1999);
    expect(parsePriceToMinor("1.15")).toBe(115);
  });

  it("rechaza vacío, negativos, texto y más de dos decimales", () => {
    for (const bad of ["", "-5", "abc", "1.234", "1..2", "1e3", "12,"]) {
      expect(parsePriceToMinor(bad), bad).toBeNull();
    }
  });
});

describe("minorToInput", () => {
  it("devuelve el texto editable con dos decimales", () => {
    expect(minorToInput(20000)).toBe("200.00");
    expect(minorToInput(7)).toBe("0.07");
    expect(minorToInput(1999)).toBe("19.99");
  });
});
