import { describe, expect, it } from "vitest";
import {
  addDays,
  isPlainDate,
  localDateToInstant,
  mondayOf,
  todayInZone,
  toWallClock,
  wallClockToInstant,
  weekdayOf,
} from "./agenda-time";

const MANAGUA = "America/Managua";

describe("hora de pared de la sucursal", () => {
  it("una cita en UTC cae en la hora de Managua", () => {
    expect(toWallClock("2026-11-18T15:30:00.000Z", MANAGUA)).toBe("2026-11-18T09:30:00");
  });

  it("no depende de la zona del navegador: la misma cita da otra hora solo si cambia la sucursal", () => {
    expect(toWallClock("2026-11-18T15:30:00.000Z", "Europe/Madrid")).toBe("2026-11-18T16:30:00");
  });

  it("una cita de madrugada en UTC pertenece al día anterior de la sucursal", () => {
    expect(toWallClock("2026-11-19T02:00:00.000Z", MANAGUA)).toBe("2026-11-18T20:00:00");
  });

  it("respeta el horario de verano de la zona de la sucursal", () => {
    expect(toWallClock("2026-07-01T12:00:00.000Z", "America/New_York")).toBe("2026-07-01T08:00:00");
    expect(toWallClock("2026-12-01T12:00:00.000Z", "America/New_York")).toBe("2026-12-01T07:00:00");
  });

  it("ida y vuelta entre instante y hora de pared", () => {
    const wall = toWallClock("2026-11-18T15:30:00.000Z", MANAGUA);
    expect(wallClockToInstant(wall, MANAGUA)).toBe("2026-11-18T15:30:00.000Z");
  });

  it("una hora de pared inválida no produce instante", () => {
    expect(wallClockToInstant("2026-13-45T09:00:00", MANAGUA)).toBeNull();
  });

  it("lee el Date del calendario como hora de pared, no como instante", () => {
    expect(localDateToInstant(new Date(2026, 10, 18, 9, 30), MANAGUA)).toBe(
      "2026-11-18T15:30:00.000Z",
    );
  });
});

describe("días de la sucursal", () => {
  it("hoy se calcula en la zona de la sucursal", () => {
    const lateNightUtc = new Date("2026-11-19T02:00:00.000Z");
    expect(todayInZone(MANAGUA, lateNightUtc)).toBe("2026-11-18");
    expect(todayInZone("Asia/Tokyo", lateNightUtc)).toBe("2026-11-19");
  });

  it("reconoce solo días reales del calendario", () => {
    expect(isPlainDate("2026-11-18")).toBe(true);
    expect(isPlainDate("2026-13-45")).toBe(false);
    expect(isPlainDate("2026-02-30")).toBe(false);
    expect(isPlainDate("mañana")).toBe(false);
  });

  it("suma días cruzando meses y años", () => {
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });

  it("la semana empieza en lunes, también desde un domingo", () => {
    expect(mondayOf("2026-11-18")).toBe("2026-11-16");
    expect(mondayOf("2026-11-22")).toBe("2026-11-16");
    expect(mondayOf("2026-11-16")).toBe("2026-11-16");
  });

  it("el día de la semana usa 0 para domingo, como los horarios", () => {
    expect(weekdayOf("2026-11-22")).toBe(0);
    expect(weekdayOf("2026-11-16")).toBe(1);
  });
});
