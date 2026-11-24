import { screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { renderWithI18n } from "../../../../../test/render-with-i18n";
import type { AgendaViewEvent, AgendaViewProps } from "../types";
import AgendaList from "./agenda-list";

const DAY = "2026-11-18";
const at = (clock: string) => `${DAY}T${clock}:00`;

const event = (overrides: Partial<AgendaViewEvent>): AgendaViewEvent => ({
  id: "cita",
  resourceId: "luis",
  start: at("09:00"),
  end: at("10:00"),
  tone: "confirmed",
  title: "Ana Ruiz",
  subtitle: "Corte de dama",
  meta: "9:00 a. m. a 10:00 a. m., Confirmada",
  movable: true,
  ...overrides,
});

function props(overrides: Partial<AgendaViewProps> = {}): AgendaViewProps {
  return {
    mode: "day",
    date: DAY,
    timeZone: "America/Managua",
    resources: [
      { id: "rosa", title: "Rosa Martínez", detail: "1 cita" },
      { id: "luis", title: "Luis Pérez", detail: "2 citas" },
    ],
    events: [
      event({
        id: "b",
        resourceId: "luis",
        title: "Eva Luna",
        start: at("11:00"),
        end: at("11:30"),
      }),
      event({ id: "a", resourceId: "luis", title: "Ana Ruiz" }),
      event({
        id: "c",
        resourceId: "rosa",
        title: "Luz Mora",
        start: at("10:00"),
        end: at("10:45"),
      }),
    ],
    blocks: [{ resourceId: "luis", start: at("12:00"), end: at("13:00") }],
    range: { startMinute: 8 * 60, endMinute: 14 * 60 },
    stepMinutes: 15,
    now: null,
    onSelectSlot: vi.fn(),
    ...overrides,
  };
}

const appointmentNames = () =>
  within(screen.getByRole("list", { name: "Citas del día" }))
    .queryAllByRole("button", { name: /Ana Ruiz|Eva Luna|Luz Mora/ })
    .map((item) => item.getAttribute("aria-label")?.split(",")[0]);

describe("AgendaList (celular)", () => {
  it("con «Todos» lista las citas de todo el equipo por hora y sin huecos", async () => {
    await renderWithI18n(<AgendaList {...props()} />);

    const tabs = screen.getByRole("tablist", { name: "Profesional" });
    expect(within(tabs).getByRole("tab", { name: /Todos/ }).getAttribute("aria-selected")).toBe(
      "true",
    );
    expect(appointmentNames()).toEqual(["Ana Ruiz", "Luz Mora", "Eva Luna"]);
    expect(screen.queryByRole("button", { name: /^Libre/ })).toBeNull();
  });

  it("al elegir un profesional muestra solo sus citas y sus huecos libres", async () => {
    const { user } = await renderWithI18n(<AgendaList {...props()} />);

    await user.click(screen.getByRole("tab", { name: /Luis Pérez/ }));

    expect(appointmentNames()).toEqual(["Ana Ruiz", "Eva Luna"]);
    const free = screen.getAllByRole("button", { name: /^Libre/ });
    // 8:00–9:00, 10:00–11:00, 11:30–12:00 and 1:00–2:00 p. m.; the closed hour is not free.
    expect(free).toHaveLength(4);
    expect(free[0]?.textContent).toContain("8:00");
    expect(free[0]?.textContent).toContain("1 h");
  });

  it("tocar un hueco libre propone esa hora de la sucursal con ese profesional", async () => {
    const onSelectSlot = vi.fn();
    const { user } = await renderWithI18n(<AgendaList {...props({ onSelectSlot })} />);
    await user.click(screen.getByRole("tab", { name: /Luis Pérez/ }));

    await user.click(screen.getAllByRole("button", { name: /^Libre/ })[1]!);

    expect(onSelectSlot).toHaveBeenCalledOnce();
    const slot = onSelectSlot.mock.calls[0]![0] as { startsAt: string; resourceId: string };
    expect(slot.resourceId).toBe("luis");
    // 10:00 in Managua (UTC-6) is 16:00 UTC, whatever the phone's zone.
    expect(new Date(slot.startsAt).toISOString()).toBe("2026-11-18T16:00:00.000Z");
  });

  it("sin permiso para crear, los huecos se ven pero no se pueden tocar", async () => {
    const { user } = await renderWithI18n(<AgendaList {...props({ onSelectSlot: undefined })} />);
    await user.click(screen.getByRole("tab", { name: /Luis Pérez/ }));

    expect(screen.queryByRole("button", { name: /^Libre/ })).toBeNull();
    expect(screen.getAllByText(/^Libre/).length).toBeGreaterThan(0);
  });

  it("tocar una cita abre su detalle", async () => {
    const onOpenEvent = vi.fn();
    const { user } = await renderWithI18n(<AgendaList {...props({ onOpenEvent })} />);

    await user.click(screen.getByRole("button", { name: /Eva Luna/ }));

    expect(onOpenEvent).toHaveBeenCalledWith("b");
  });

  it("con un solo profesional no hay chips: va directo a su día con huecos", async () => {
    await renderWithI18n(
      <AgendaList
        {...props({
          resources: [{ id: "luis", title: "Luis Pérez", detail: "2 citas" }],
          events: [event({ id: "a" })],
        })}
      />,
    );

    expect(screen.queryByRole("tablist")).toBeNull();
    expect(screen.getAllByRole("button", { name: /^Libre/ }).length).toBeGreaterThan(0);
  });

  it("la línea de ahora queda entre lo pasado y lo que viene", async () => {
    await renderWithI18n(<AgendaList {...props({ now: at("10:40") })} />);

    const items = within(screen.getByRole("list", { name: "Citas del día" })).getAllByRole(
      "listitem",
    );
    const texts = items.map((item) => item.textContent ?? "");
    const nowIndex = texts.findIndex((text) => text.includes("10:40"));
    expect(nowIndex).toBeGreaterThan(texts.findIndex((text) => text.includes("Luz Mora")));
    expect(nowIndex).toBeLessThan(texts.findIndex((text) => text.includes("Eva Luna")));
  });
});
