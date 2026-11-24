import type { components } from "@ceiba/api-client";
import { describe, expect, it } from "vitest";
import {
  NO_RESOURCE,
  closeUnknownHours,
  closedBlocks,
  mergeProfessionalColumns,
  openForProfessional,
  openForResource,
  timeRange,
  upcomingArrivals,
  visibleAppointments,
} from "./agenda-model";

type Appointment = components["schemas"]["AgendaAppointment"];
type Slot = components["schemas"]["WeeklyScheduleSlot"];
type TimeOff = components["schemas"]["TimeOff"];

const MANAGUA = "America/Managua";
const WEDNESDAY = "2026-11-18";

const appointment = (overrides: Partial<Appointment>): Appointment =>
  ({
    id: "a1",
    branch_id: "b1",
    professional_id: "p1",
    resource_id: null,
    customer_id: "c1",
    customer_name: "Ana Ruiz",
    status: "confirmed",
    starts_at: "2026-11-18T15:00:00.000Z",
    ends_at: "2026-11-18T15:30:00.000Z",
    ...overrides,
  }) as Appointment;

const slot = (weekday: number, starts: string, ends: string): Slot =>
  ({ id: `${weekday}${starts}`, weekday, starts_at_local: starts, ends_at_local: ends }) as Slot;

const timeOff = (starts_at: string, ends_at: string): TimeOff =>
  ({ id: "t1", starts_at, ends_at }) as TimeOff;

describe("citas visibles en la grilla", () => {
  it("las canceladas y reprogramadas liberan el hueco y no se dibujan", () => {
    const list = [
      appointment({ id: "a", status: "scheduled" }),
      appointment({ id: "b", status: "cancelled" }),
      appointment({ id: "c", status: "rescheduled" }),
      appointment({ id: "d", status: "no_show" }),
      appointment({ id: "e", status: "completed" }),
      appointment({ id: "f", status: "checked_in" }),
    ];
    expect(visibleAppointments(list).map((item) => item.id)).toEqual(["a", "d", "e", "f"]);
  });
});

describe("columnas de profesionales", () => {
  const person = (id: string, branch_ids: string[]) => ({ id, branch_ids });
  const names: Record<string, string> = { p1: "Rosa", p3: "Ana" };
  const nameOf = (id: string) => names[id] ?? "Profesional";

  it("une los asignados a la sucursal con los que tienen citas aunque ya no estén asignados", () => {
    const columns = mergeProfessionalColumns({
      branchId: "b1",
      professionals: [person("p1", ["b1"]), person("p2", ["b2"])],
      appointments: [appointment({ professional_id: "p3" })],
      nameOf,
    });
    expect(columns).toEqual([
      { id: "p1", title: "Rosa" },
      { id: "p3", title: "Ana" },
    ]);
  });

  it("sin perfil conocido usa el texto de respaldo y no pierde la cita", () => {
    const columns = mergeProfessionalColumns({
      branchId: "b1",
      professionals: [],
      appointments: [appointment({ professional_id: "p9" })],
      nameOf,
    });
    expect(columns).toEqual([{ id: "p9", title: "Profesional" }]);
  });
});

describe("franjas abiertas (la misma regla del motor de disponibilidad)", () => {
  const branch = [slot(3, "08:00", "18:00")];

  it("un profesional abre en la intersección de la sucursal y su horario", () => {
    expect(openForProfessional(branch, [slot(3, "07:00", "12:00")], 3)).toEqual([[480, 720]]);
  });

  it("un profesional sin franjas propias queda cerrado", () => {
    expect(openForProfessional(branch, [], 3)).toEqual([]);
  });

  it("sin horario de sucursal disponible (rol profesional) usa solo el propio", () => {
    expect(openForProfessional(null, [slot(3, "07:00", "12:00")], 3)).toEqual([[420, 720]]);
  });

  it("un recurso sin franjas hereda la sucursal y con franjas intersecta", () => {
    expect(openForResource(branch, [], 3)).toEqual([[480, 1080]]);
    expect(openForResource(branch, [slot(3, "17:00", "20:00")], 3)).toEqual([[1020, 1080]]);
  });
});

describe("bloqueos", () => {
  const range = { startMinute: 480, endMinute: 1080 };

  it("marca lo cerrado alrededor de las franjas abiertas", () => {
    const blocks = closedBlocks({
      columns: [{ id: "p1", openOn: () => [[540, 720]], timeOffs: [] }],
      days: [WEDNESDAY],
      timeZone: MANAGUA,
      range,
    });
    expect(blocks).toEqual([
      { resourceId: "p1", start: "2026-11-18T08:00:00", end: "2026-11-18T09:00:00" },
      { resourceId: "p1", start: "2026-11-18T12:00:00", end: "2026-11-18T18:00:00" },
    ]);
  });

  it("recorta una ausencia de varios días al día visible", () => {
    const blocks = closedBlocks({
      columns: [
        {
          id: "p1",
          openOn: () => [[480, 1080]],
          timeOffs: [timeOff("2026-11-17T20:00:00Z", "2026-11-18T16:00:00Z")],
        },
      ],
      days: [WEDNESDAY],
      timeZone: MANAGUA,
      range,
    });
    expect(blocks).toEqual([
      { resourceId: "p1", start: "2026-11-18T08:00:00", end: "2026-11-18T10:00:00" },
    ]);
  });

  it("una ausencia de otro día no bloquea nada", () => {
    const blocks = closedBlocks({
      columns: [
        {
          id: "p1",
          openOn: () => [[480, 1080]],
          timeOffs: [timeOff("2026-11-20T15:00:00Z", "2026-11-20T16:00:00Z")],
        },
      ],
      days: [WEDNESDAY],
      timeZone: MANAGUA,
      range,
    });
    expect(blocks).toEqual([]);
  });
});

describe("rango horario visible", () => {
  it("sin datos usa la jornada por defecto", () => {
    expect(timeRange({ openings: [], appointments: [], timeZone: MANAGUA })).toEqual({
      startMinute: 480,
      endMinute: 1080,
    });
  });

  it("se amplía en horas completas para no esconder una cita fuera de horario", () => {
    const range = timeRange({
      openings: [[540, 1020]],
      appointments: [
        appointment({
          starts_at: "2026-11-18T13:20:00.000Z",
          ends_at: "2026-11-19T01:10:00.000Z",
        }),
      ],
      timeZone: MANAGUA,
    });
    expect(range).toEqual({ startMinute: 420, endMinute: 1200 });
  });
});

describe("rango horario nunca vacío", () => {
  it("una cita de duración cero a la hora en punto deja al menos una hora visible", () => {
    const range = timeRange({
      openings: [],
      appointments: [
        appointment({
          starts_at: "2026-11-18T15:00:00.000Z",
          ends_at: "2026-11-18T15:00:00.000Z",
        }),
      ],
      timeZone: MANAGUA,
    });
    expect(range).toEqual({ startMinute: 540, endMinute: 600 });
  });
});

describe("próximas llegadas", () => {
  const now = new Date("2026-11-18T15:00:00.000Z");

  it("conserva a quien llega tarde durante media hora, para poder marcar su llegada", () => {
    const list = [
      appointment({ id: "tarde", starts_at: "2026-11-18T14:40:00.000Z" }),
      appointment({ id: "muy-tarde", starts_at: "2026-11-18T14:20:00.000Z" }),
    ];
    expect(upcomingArrivals(list, now).map((item) => item.id)).toEqual(["tarde"]);
  });

  it("lista por hora las citas por llegar de la próxima hora", () => {
    const list = [
      appointment({ id: "later", starts_at: "2026-11-18T15:40:00.000Z" }),
      appointment({ id: "soon", starts_at: "2026-11-18T15:10:00.000Z", status: "scheduled" }),
      appointment({ id: "edge", starts_at: "2026-11-18T16:00:00.000Z" }),
      appointment({ id: "past", starts_at: "2026-11-18T14:29:00.000Z" }),
      appointment({ id: "here", starts_at: "2026-11-18T15:20:00.000Z", status: "checked_in" }),
      appointment({ id: "gone", starts_at: "2026-11-18T15:20:00.000Z", status: "cancelled" }),
    ];
    expect(upcomingArrivals(list, now).map((item) => item.id)).toEqual(["soon", "later"]);
  });
});

it("expone una columna para las citas sin recurso", () => {
  expect(NO_RESOURCE).toBe("sin-recurso");
});

describe("closeUnknownHours", () => {
  const range = { startMinute: 8 * 60, endMinute: 18 * 60 };
  const DAY = "2026-11-18";

  it("cierra el día entero de quien todavía no tiene horario cargado y respeta lo conocido", () => {
    const known = [{ resourceId: "rosa", start: `${DAY}T12:00:00`, end: `${DAY}T13:00:00` }];
    expect(
      closeUnknownHours({
        blocks: known,
        ownerIds: ["rosa", "luis"],
        knownIds: new Set(["rosa"]),
        days: [DAY],
        range,
      }),
    ).toEqual([...known, { resourceId: "luis", start: `${DAY}T08:00:00`, end: `${DAY}T18:00:00` }]);
  });

  it("con todo conocido devuelve los mismos bloques", () => {
    const blocks = [{ resourceId: "luis", start: `${DAY}T08:00:00`, end: `${DAY}T09:00:00` }];
    expect(
      closeUnknownHours({
        blocks,
        ownerIds: ["luis"],
        knownIds: new Set(["luis"]),
        days: [DAY],
        range,
      }),
    ).toBe(blocks);
  });

  it("sin nada conocido cierra cada día de cada fila (adversarial)", () => {
    expect(
      closeUnknownHours({
        blocks: [],
        ownerIds: ["luis"],
        knownIds: new Set(),
        days: [DAY, "2026-11-19"],
        range,
      }),
    ).toHaveLength(2);
  });
});
