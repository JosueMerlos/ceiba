import { describe, expect, it } from "vitest";
import { formatCurrency, formatDate, formatDateTime, formatNumber, formatTime } from "../src";

// Intl con es-NI: los formatos salen del runtime, no de cadenas escritas a mano.
describe("formatos es-NI", () => {
  it("formatea córdobas y dólares con su símbolo", () => {
    expect(formatCurrency(1250.5, "NIO")).toMatch(/C\$\s?1,250\.50|NIO\s?1,250\.50/);
    expect(formatCurrency(35, "USD")).toMatch(/US\$\s?35\.00|\$\s?35\.00/);
  });

  it("formatea números con separador de miles", () => {
    expect(formatNumber(1234567.891)).toBe("1,234,567.891");
  });

  it("formatea la fecha SIEMPRE en la zona indicada, nunca en la del navegador", () => {
    // 2026-11-09 03:30 UTC es el 8 de noviembre a las 21:30 en Managua (UTC-6).
    const instant = "2026-11-09T03:30:00Z";

    expect(formatDate(instant, "America/Managua")).toContain("8");
    expect(formatDate(instant, "UTC")).toContain("9");
  });

  it("formatea la hora en la zona de la sucursal", () => {
    const instant = "2026-11-09T15:05:00Z";

    expect(formatTime(instant, "America/Managua")).toMatch(/9:05/);
  });

  it("formatea fecha y hora juntas", () => {
    const text = formatDateTime("2026-11-09T15:05:00Z", "America/Managua");

    expect(text).toMatch(/noviembre/);
    expect(text).toMatch(/9:05/);
  });
});
