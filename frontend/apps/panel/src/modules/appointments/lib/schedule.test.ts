import { describe, expect, it } from "vitest";
import { toDrafts, toPayload, validateSlots, WEEK_ORDER, type SlotDraft } from "./schedule";

const draft = (key: string, weekday: number, start: string, end: string): SlotDraft => ({
  key,
  weekday,
  start,
  end,
});

describe("validateSlots", () => {
  it("no marca franjas válidas ni franjas contiguas (fin = inicio de la siguiente)", () => {
    const problems = validateSlots([
      draft("a", 1, "09:00", "13:00"),
      draft("b", 1, "13:00", "17:00"),
      draft("c", 2, "09:00", "13:00"),
    ]);
    expect(problems.size).toBe(0);
  });

  it("marca solape el mismo día en las dos franjas", () => {
    const problems = validateSlots([
      draft("a", 1, "09:00", "13:00"),
      draft("b", 1, "12:00", "15:00"),
    ]);
    expect(problems.get("a")).toBe("overlap");
    expect(problems.get("b")).toBe("overlap");
  });

  it("el mismo horario en otro día NO es solape (adversarial: no comparar entre días)", () => {
    expect(
      validateSlots([draft("a", 1, "09:00", "13:00"), draft("b", 2, "09:00", "13:00")]).size,
    ).toBe(0);
  });

  it("marca fin igual o anterior al inicio", () => {
    const problems = validateSlots([
      draft("a", 1, "13:00", "13:00"),
      draft("b", 2, "15:00", "09:00"),
    ]);
    expect(problems.get("a")).toBe("endBeforeStart");
    expect(problems.get("b")).toBe("endBeforeStart");
  });

  it("marca la hora vacía como requerida y no la usa para detectar solapes", () => {
    const problems = validateSlots([draft("a", 1, "", "13:00"), draft("b", 1, "09:00", "12:00")]);
    expect(problems.get("a")).toBe("required");
    expect(problems.has("b")).toBe(false);
  });

  it("un solape de tres franjas marca solo las que se cruzan", () => {
    const problems = validateSlots([
      draft("a", 3, "08:00", "10:00"),
      draft("b", 3, "09:00", "11:00"),
      draft("c", 3, "14:00", "16:00"),
    ]);
    expect([...problems.keys()].sort()).toEqual(["a", "b"]);
  });
});

describe("conversión con el contrato", () => {
  it("WEEK_ORDER muestra lunes primero y domingo (0) al final", () => {
    expect(WEEK_ORDER).toEqual([1, 2, 3, 4, 5, 6, 0]);
  });

  it("toDrafts y toPayload son inversas y el payload sale ordenado por día y hora", () => {
    const drafts = toDrafts([
      { id: "x", weekday: 0, starts_at_local: "10:00", ends_at_local: "12:00" },
      { id: "y", weekday: 1, starts_at_local: "14:00", ends_at_local: "18:00" },
      { id: "z", weekday: 1, starts_at_local: "08:00", ends_at_local: "12:00" },
    ]);
    expect(toPayload(drafts)).toEqual({
      slots: [
        { weekday: 0, starts_at_local: "10:00", ends_at_local: "12:00" },
        { weekday: 1, starts_at_local: "08:00", ends_at_local: "12:00" },
        { weekday: 1, starts_at_local: "14:00", ends_at_local: "18:00" },
      ],
    });
  });
});
