import { describe, expect, it } from "vitest";
import { availableActions, nearbyOwnStarts } from "./agenda-actions";

const STARTED = new Date("2026-11-18T16:00:00.000Z");
const BEFORE = new Date("2026-11-18T14:00:00.000Z");
const starts_at = "2026-11-18T15:00:00.000Z";

describe("acciones de una cita", () => {
  const staff = { manage: true, own: false };
  const professional = { manage: false, own: true };

  it("recepción puede confirmar, marcar llegada, cancelar y mover una cita por confirmar", () => {
    expect(availableActions({ status: "scheduled", starts_at }, staff, BEFORE)).toEqual([
      "confirm",
      "check_in",
      "reschedule",
      "cancel",
    ]);
  });

  it("no asistió solo aparece cuando la cita ya empezó", () => {
    expect(availableActions({ status: "confirmed", starts_at }, staff, STARTED)).toContain(
      "no_show",
    );
    expect(availableActions({ status: "confirmed", starts_at }, staff, BEFORE)).not.toContain(
      "no_show",
    );
  });

  it("una cita que llegó solo se completa", () => {
    expect(availableActions({ status: "checked_in", starts_at }, staff, STARTED)).toEqual([
      "complete",
    ]);
  });

  it("el profesional nunca cancela ni reprograma", () => {
    const actions = availableActions({ status: "confirmed", starts_at }, professional, STARTED);
    expect(actions).toEqual(["check_in", "no_show"]);
  });

  it("sin permisos de edición no hay acciones", () => {
    expect(
      availableActions({ status: "confirmed", starts_at }, { manage: false, own: false }, STARTED),
    ).toEqual([]);
  });

  it.each(["completed", "no_show", "cancelled", "rescheduled"] as const)(
    "una cita %s ya no admite acciones",
    (status) => {
      expect(availableActions({ status, starts_at }, staff, STARTED)).toEqual([]);
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
