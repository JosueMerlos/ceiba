// The browser's zone must never leak into the output: run as if the machine were in Madrid.
process.env.TZ = "Europe/Madrid";

import { describe, expect, it } from "vitest";
import {
  formatClock,
  formatCurrency,
  formatDate,
  formatDateTime,
  formatNumber,
  formatPlainDate,
  formatTime,
} from "../src";

const NBSP = "\u00a0";
const MANAGUA = "America/Managua";

// Intl with es-NI: formats come from the runtime, not from hand-written strings.
describe("formatos es-NI", () => {
  it("corre con una zona de proceso distinta de la de la sucursal", () => {
    // Madrid is UTC+1 in December; Managua is UTC-6.
    expect(new Date("2026-12-14T15:00:00Z").getTimezoneOffset()).toBe(-60);
  });

  it("formatea córdobas y dólares con su símbolo", () => {
    expect(formatCurrency(1250.5, "NIO")).toMatch(/C\$\s?1,250\.50|NIO\s?1,250\.50/);
    expect(formatCurrency(35, "USD")).toMatch(/US\$\s?35\.00|\$\s?35\.00/);
  });

  it("formatea números con separador de miles", () => {
    expect(formatNumber(1234567.891)).toBe("1,234,567.891");
  });

  describe("hora", () => {
    it("lee un instante en la zona de la sucursal como «9:00 a. m.»", () => {
      expect(formatTime("2026-12-14T15:00:00Z", MANAGUA)).toBe(`9:00${NBSP}a.${NBSP}m.`);
    });

    it("mediodía es p. m. y medianoche es 12 a. m.", () => {
      expect(formatTime("2026-12-14T18:00:00Z", MANAGUA)).toBe(`12:00${NBSP}p.${NBSP}m.`);
      expect(formatTime("2026-12-14T06:00:00Z", MANAGUA)).toBe(`12:00${NBSP}a.${NBSP}m.`);
    });

    it("formatea una hora de pared «HH:mm» sin zona", () => {
      expect(formatClock("21:30")).toBe(`9:30${NBSP}p.${NBSP}m.`);
      expect(formatClock("00:05")).toBe(`12:05${NBSP}a.${NBSP}m.`);
      expect(formatClock("09:00")).toBe(`9:00${NBSP}a.${NBSP}m.`);
    });

    it("nunca deja espacios normales ni estrechos de ICU", () => {
      const outputs = [
        formatTime("2026-12-14T15:00:00Z", MANAGUA),
        formatClock("13:15"),
        formatDateTime("2026-12-14T15:00:00Z", MANAGUA),
      ];
      for (const text of outputs) expect(text).not.toMatch(/\d [ap]\.|[ap]\. m\.|\u202f/);
    });
  });

  describe("fecha", () => {
    it("lee un instante como «lun 14 dic 2026» en la zona de la sucursal", () => {
      expect(formatDate("2026-12-14T15:00:00Z", MANAGUA)).toBe(`lun${NBSP}14${NBSP}dic${NBSP}2026`);
    });

    it("de noche en Managua sigue siendo el mismo día aunque en UTC ya sea el siguiente", () => {
      expect(formatDate("2026-12-15T03:30:00Z", MANAGUA)).toBe(`lun${NBSP}14${NBSP}dic${NBSP}2026`);
    });

    it("formatea una fecha civil «yyyy-MM-dd» sin que la zona mueva el día", () => {
      expect(formatPlainDate("2026-12-14")).toBe(`lun${NBSP}14${NBSP}dic${NBSP}2026`);
      expect(formatPlainDate("2026-01-01")).toBe(`jue${NBSP}1${NBSP}ene${NBSP}2026`);
    });

    it("junta fecha y hora con el mismo formato", () => {
      expect(formatDateTime("2026-12-14T15:00:00Z", MANAGUA)).toBe(
        `lun${NBSP}14${NBSP}dic${NBSP}2026, 9:00${NBSP}a.${NBSP}m.`,
      );
    });
  });
});
