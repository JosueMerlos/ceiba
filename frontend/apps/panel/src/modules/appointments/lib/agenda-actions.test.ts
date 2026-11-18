import { describe, expect, it } from "vitest";
import { appointmentActions, nearbyOwnStarts } from "./agenda-actions";

const STARTED = new Date("2026-11-18T16:00:00.000Z");
const BEFORE = new Date("2026-11-18T14:00:00.000Z");
const starts_at = "2026-11-18T15:00:00.000Z";

describe("acciones de una cita", () => {
  const staff = { manage: true, own: false };
  const professional = { manage: false, own: true };

  it("recepción puede confirmar, marcar llegada, cancelar y mover una cita por confirmar", () => {
    expect(appointmentActions({ status: "scheduled", starts_at }, staff, BEFORE)).toEqual({
      status: ["confirm", "check_in"],
      canReschedule: true,
      canCancel: true,
    });
  });

  it("no asistió solo aparece cuando la cita ya empezó", () => {
    const action = (now: Date) =>
      appointmentActions({ status: "confirmed", starts_at }, staff, now).status;
    expect(action(STARTED)).toContain("no_show");
    expect(action(BEFORE)).not.toContain("no_show");
  });

  it("una cita que llegó solo se completa", () => {
    expect(appointmentActions({ status: "checked_in", starts_at }, staff, STARTED)).toEqual({
      status: ["complete"],
      canReschedule: false,
      canCancel: false,
    });
  });

  it("el profesional nunca cancela ni reprograma", () => {
    expect(appointmentActions({ status: "confirmed", starts_at }, professional, STARTED)).toEqual({
      status: ["check_in", "no_show"],
      canReschedule: false,
      canCancel: false,
    });
  });

  it("sin permisos de edición no hay acciones", () => {
    expect(
      appointmentActions(
        { status: "confirmed", starts_at },
        { manage: false, own: false },
        STARTED,
      ),
    ).toEqual({ status: [], canReschedule: false, canCancel: false });
  });

  it.each(["completed", "no_show", "cancelled", "rescheduled"] as const)(
    "una cita %s ya no admite acciones",
    (status) => {
      expect(appointmentActions({ status, starts_at }, staff, STARTED)).toEqual({
        status: [],
        canReschedule: false,
        canCancel: false,
      });
    },
  );
});

describe("inicios cercanos a la propia cita", () => {
  it("ofrece los inicios que solapan la cita, que disponibilidad cuenta como ocupados", () => {
    const appointment = { starts_at, ends_at: "2026-11-18T15:30:00.000Z" };
    expect(nearbyOwnStarts(appointment, 15)).toEqual([
      "2026-11-18T14:45:00.000Z",
      "2026-11-18T15:15:00.000Z",
    ]);
  });
});
