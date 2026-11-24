import { render, screen, waitFor, within } from "@testing-library/react";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { AgendaViewEvent, AgendaViewProps } from "../types";
import EventCalendarAdapter from "./event-calendar";

const DAY = "2026-11-18";
const browserZone = process.env.TZ;

// A browser far from the branch: nothing drawn may depend on the machine's zone.
beforeAll(() => {
  process.env.TZ = "Europe/Madrid";
});
afterAll(() => {
  process.env.TZ = browserZone;
});

const event = (overrides: Partial<AgendaViewEvent> = {}): AgendaViewEvent => ({
  id: "cita",
  resourceId: "luis",
  start: `${DAY}T09:00:00`,
  end: `${DAY}T10:00:00`,
  tone: "confirmed",
  title: "Ana Ruiz",
  subtitle: "Corte de dama",
  meta: "9:00 a. m. a 10:00 a. m. · Confirmada",
  movable: true,
  ...overrides,
});

function props(overrides: Partial<AgendaViewProps> = {}): AgendaViewProps {
  return {
    mode: "day",
    date: DAY,
    timeZone: "America/Managua",
    resources: [
      { id: "rosa", title: "Rosa Martínez", detail: "0 citas" },
      { id: "luis", title: "Luis Pérez", detail: "1 cita" },
    ],
    events: [event()],
    blocks: [],
    range: { startMinute: 8 * 60, endMinute: 18 * 60 },
    stepMinutes: 15,
    now: null,
    ...overrides,
  };
}

/** The library lays rows out on a grid: an event's row is the row header at the same grid line. */
function rowOf(card: HTMLElement) {
  const placed = card.closest<HTMLElement>(".ec-event")!;
  const line = Number(/grid-area:\s*(\d+)/.exec(placed.getAttribute("style") ?? "")?.[1]);
  const heads = placed.closest(".ec-body")!.querySelectorAll(".ec-row-head");
  return heads[line - 1]?.querySelector("[role=group]")?.getAttribute("aria-label");
}

const card = (name: RegExp | string) => screen.findByRole("button", { name });

describe("EventCalendarAdapter: día en filas", () => {
  it("pinta cada profesional en una fila y la cita en la suya, a la hora de la sucursal", async () => {
    render(<EventCalendarAdapter {...props()} />);

    expect(await screen.findByRole("group", { name: "Rosa Martínez" })).toBeTruthy();
    expect(screen.getByRole("group", { name: "Luis Pérez" })).toBeTruthy();
    const appointment = await card(/Ana Ruiz/);
    expect(rowOf(appointment)).toBe("Luis Pérez");
    expect(appointment.closest(".ec-timeline")).toBeTruthy();
    // 9:00 at the branch, one hour after an 8:00 opening: two 30-minute slots from the start of the row.
    const placed = appointment.closest<HTMLElement>(".ec-event")!;
    const slotWidth = Number.parseFloat(placed.style.insetInlineStart) / 2;
    expect(slotWidth).toBeGreaterThan(0);
    expect(placed.style.insetInlineStart).toBe(`${slotWidth * 2}px`);
    expect(appointment.textContent).toContain("9:00");
  });

  it("en compacta muestra iniciales, nombre o nombre y servicio según el ancho de la cita", async () => {
    render(
      <EventCalendarAdapter
        {...props({
          density: "compact",
          events: [
            event({ id: "corta", title: "Eva Luna", start: `${DAY}T09:00:00`, end: `${DAY}T09:15:00` }),
            event({ id: "media", title: "Raúl Mora", start: `${DAY}T10:00:00`, end: `${DAY}T10:30:00` }),
            event({ id: "larga", title: "Ana Ruiz", start: `${DAY}T11:00:00`, end: `${DAY}T12:00:00` }),
          ],
        })}
      />,
    );

    const short = await card(/Eva Luna/);
    const visible = (node: HTMLElement) =>
      [...node.querySelectorAll<HTMLElement>("[data-part]")]
        .filter((part) => !part.classList.contains("sr-only"))
        .map((part) => part.dataset.part);
    expect(visible(short)).toEqual(["initials"]);
    expect(within(short).getByText("EL")).toBeTruthy();
    expect(short.closest(".ec-event")?.getAttribute("title")).toContain("Eva Luna");

    expect(visible(await card(/Raúl Mora/))).toEqual(["name"]);
    expect(visible(await card(/Ana Ruiz/))).toEqual(["name", "service"]);
  });

  it("al cambiar de densidad vuelve a decidir el nivel sin remontar el calendario", async () => {
    const short = [event({ id: "media", title: "Raúl Mora", end: `${DAY}T09:45:00` })];
    const { rerender } = render(<EventCalendarAdapter {...props({ events: short })} />);
    const visible = async () =>
      [...(await card(/Raúl Mora/)).querySelectorAll<HTMLElement>("[data-part]")]
        .filter((part) => !part.classList.contains("sr-only"))
        .map((part) => part.dataset.part);
    await waitFor(async () => expect(await visible()).toEqual(["name", "service"]));
    const calendar = document.querySelector(".ec");

    rerender(<EventCalendarAdapter {...props({ events: short, density: "compact" })} />);
    await waitFor(async () => expect(await visible()).toEqual(["name"]));
    expect(document.querySelector(".ec")).toBe(calendar);
  });

  it("con recursos, las filas son los recursos y cada cita va en el suyo", async () => {
    render(
      <EventCalendarAdapter
        {...props({
          resources: [
            { id: "sillon-1", title: "Sillón 1", detail: "1 cita" },
            { id: "cabina", title: "Cabina de uñas", detail: "1 cita" },
          ],
          events: [
            event({ id: "a", resourceId: "cabina", title: "Ana Ruiz" }),
            event({ id: "b", resourceId: "sillon-1", title: "Luz Mora", start: `${DAY}T11:00:00`, end: `${DAY}T12:00:00` }),
          ],
        })}
      />,
    );

    expect(rowOf(await card(/Ana Ruiz/))).toBe("Cabina de uñas");
    expect(rowOf(await card(/Luz Mora/))).toBe("Sillón 1");
  });

  it("la línea de ahora lleva la hora de la sucursal en el encabezado", async () => {
    render(<EventCalendarAdapter {...props({ now: `${DAY}T10:40:00` })} />);

    const label = await screen.findByText("10:40 a. m.");
    expect(label.closest(".ec-header")).toBeTruthy();
  });
});
