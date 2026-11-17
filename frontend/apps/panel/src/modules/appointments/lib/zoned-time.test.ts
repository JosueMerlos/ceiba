import { describe, expect, it } from "vitest";
import { formatInZone, localToUtcIso, utcToLocalInput } from "./zoned-time";

describe("localToUtcIso", () => {
  it("convierte la hora local de Managua (UTC-6, sin horario de verano) a UTC", () => {
    expect(localToUtcIso("2026-11-20T09:00", "America/Managua")).toBe("2026-11-20T15:00:00.000Z");
  });

  it("respeta el horario de verano de la zona: Nueva York en julio es UTC-4 y en enero UTC-5", () => {
    expect(localToUtcIso("2026-07-01T09:00", "America/New_York")).toBe("2026-07-01T13:00:00.000Z");
    expect(localToUtcIso("2026-01-15T09:00", "America/New_York")).toBe("2026-01-15T14:00:00.000Z");
  });

  it("no depende de la zona del navegador: el mismo texto da instantes distintos según la sucursal", () => {
    const managua = localToUtcIso("2026-11-20T09:00", "America/Managua");
    const bogota = localToUtcIso("2026-11-20T09:00", "America/Bogota");
    expect(managua).not.toBe(bogota);
    expect(bogota).toBe("2026-11-20T14:00:00.000Z");
  });

  it("devuelve null con un texto incompleto o una zona inexistente", () => {
    expect(localToUtcIso("", "America/Managua")).toBeNull();
    expect(localToUtcIso("2026-11-20", "America/Managua")).toBeNull();
    expect(localToUtcIso("2026-13-45T25:00", "America/Managua")).toBeNull();
    expect(localToUtcIso("2026-11-20T09:00", "Mars/Olympus")).toBeNull();
  });
});

describe("utcToLocalInput y formatInZone", () => {
  it("ida y vuelta: lo que se guardó vuelve a la misma hora local", () => {
    const iso = localToUtcIso("2026-11-20T09:30", "America/Managua")!;
    expect(utcToLocalInput(iso, "America/Managua")).toBe("2026-11-20T09:30");
  });

  it("muestra el instante en la hora de la sucursal, no en la del navegador", () => {
    expect(formatInZone("2026-11-20T15:00:00.000Z", "America/Managua")).toContain("9:00");
    expect(formatInZone("2026-11-20T15:00:00.000Z", "America/Bogota")).toContain("10:00");
  });
});
