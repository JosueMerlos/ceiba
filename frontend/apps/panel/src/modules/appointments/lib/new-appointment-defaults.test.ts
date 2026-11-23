import { describe, expect, it } from "vitest";
import { newAppointmentDefaults } from "./new-appointment-defaults";

const professionals = [{ id: "rosa" }, { id: "luis" }];
const at10 = "2026-11-18T16:00:00.000Z";

describe("profesional inicial de una cita nueva", () => {
  it("en la vista por profesional toma el de la columna clicada", () => {
    const defaults = newAppointmentDefaults({
      mode: "professionals",
      slot: { startsAt: at10, resourceId: "luis" },
      weekProfessionalId: null,
      professionals,
    });
    expect(defaults.professionalId).toBe("luis");
  });

  it("clicar a la misma hora en otra columna cambia la clave, para que el panel no conserve al anterior", () => {
    const options = { mode: "professionals" as const, weekProfessionalId: null, professionals };
    const rosa = newAppointmentDefaults({
      ...options,
      slot: { startsAt: at10, resourceId: "rosa" },
    });
    const luis = newAppointmentDefaults({
      ...options,
      slot: { startsAt: at10, resourceId: "luis" },
    });
    expect(rosa.key).not.toBe(luis.key);
    expect([rosa.professionalId, luis.professionalId]).toEqual(["rosa", "luis"]);
  });

  it("en la semana de un profesional propone a ese profesional, desde la grilla o desde el botón", () => {
    for (const slot of [{ startsAt: at10, resourceId: null }, null]) {
      expect(
        newAppointmentDefaults({ mode: "week", slot, weekProfessionalId: "luis", professionals })
          .professionalId,
      ).toBe("luis");
    }
  });

  it("en la vista por recurso la columna es un sillón, no un profesional: propone el primero disponible", () => {
    const defaults = newAppointmentDefaults({
      mode: "resources",
      slot: { startsAt: at10, resourceId: "sillon-1" },
      weekProfessionalId: null,
      professionals,
    });
    expect(defaults.professionalId).toBe("rosa");
  });

  it("una columna o semana de alguien que no se puede reservar no se propone (adversarial)", () => {
    expect(
      newAppointmentDefaults({
        mode: "professionals",
        slot: { startsAt: at10, resourceId: "pausado" },
        weekProfessionalId: null,
        professionals,
      }).professionalId,
    ).toBe("rosa");
    expect(
      newAppointmentDefaults({
        mode: "week",
        slot: null,
        weekProfessionalId: "pausado",
        professionals,
      }).professionalId,
    ).toBe("rosa");
    expect(
      newAppointmentDefaults({
        mode: "week",
        slot: null,
        weekProfessionalId: null,
        professionals: [],
      }).professionalId,
    ).toBeNull();
  });
});
