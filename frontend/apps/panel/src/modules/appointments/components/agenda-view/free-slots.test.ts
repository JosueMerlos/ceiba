import { describe, expect, it } from "vitest";
import { freeSlots } from "./free-slots";

const DAY = "2026-11-18";
const at = (clock: string) => `${DAY}T${clock}:00`;
const busy = (start: string, end: string, resourceId = "luis") => ({
  resourceId,
  start: at(start),
  end: at(end),
});

const base = {
  resourceId: "luis",
  date: DAY,
  range: { startMinute: 8 * 60, endMinute: 12 * 60 },
  minMinutes: 15,
};

describe("freeSlots", () => {
  it("encuentra los huecos entre citas, desde la apertura hasta el cierre", () => {
    expect(freeSlots({ ...base, busy: [busy("09:00", "10:00"), busy("10:30", "11:00")] })).toEqual([
      { start: at("08:00"), minutes: 60 },
      { start: at("10:00"), minutes: 30 },
      { start: at("11:00"), minutes: 60 },
    ]);
  });

  it("lo cerrado y las ausencias parten el hueco igual que una cita", () => {
    expect(freeSlots({ ...base, busy: [busy("08:00", "09:00"), busy("10:00", "12:00")] })).toEqual([
      { start: at("09:00"), minutes: 60 },
    ]);
  });

  it("solo cuenta lo del profesional pedido y lo que se solapa", () => {
    expect(
      freeSlots({
        ...base,
        busy: [busy("08:00", "11:00", "rosa"), busy("09:00", "10:00"), busy("09:30", "10:30")],
      }),
    ).toEqual([
      { start: at("08:00"), minutes: 60 },
      { start: at("10:30"), minutes: 90 },
    ]);
  });

  it("descarta los huecos más cortos que el paso de la agenda (adversarial)", () => {
    expect(
      freeSlots({
        ...base,
        busy: [busy("08:00", "08:50"), busy("09:00", "11:55")],
      }),
    ).toEqual([]);
  });

  it("lo que cae fuera del día visible no cuenta", () => {
    expect(
      freeSlots({
        ...base,
        busy: [{ resourceId: "luis", start: "2026-11-17T08:00:00", end: "2026-11-19T09:00:00" }],
      }),
    ).toEqual([]);
    expect(
      freeSlots({
        ...base,
        busy: [{ resourceId: "luis", start: "2026-11-17T08:00:00", end: "2026-11-17T18:00:00" }],
      }),
    ).toEqual([{ start: at("08:00"), minutes: 240 }]);
  });

  it("hoy no ofrece lo que ya pasó: arranca en la próxima hora del paso", () => {
    expect(freeSlots({ ...base, busy: [busy("10:00", "11:00")], notBefore: 9 * 60 + 7 })).toEqual([
      { start: at("09:15"), minutes: 45 },
      { start: at("11:00"), minutes: 60 },
    ]);
  });
});
