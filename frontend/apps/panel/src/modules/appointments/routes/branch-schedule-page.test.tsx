import { screen, fireEvent, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import {
  CATALOG,
  MANAGER_PERMISSIONS,
  READER_PERMISSIONS,
  page,
} from "../../../test/catalog-backend";
import { branch, ids, meFixture, scheduleSlot, validationProblem } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { server, signedInBackend } from "../../../test/server";

const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const SCHEDULE = `${CATALOG}/appointments/branches/${ids.branchA}/schedule`;

function scheduleBackend(slots: ReturnType<typeof scheduleSlot>[], putResponse?: () => Response) {
  const state = { puts: [] as unknown[], slots };
  server.use(
    http.get(`${CATALOG}/branches`, () => HttpResponse.json(page([centro]))),
    http.get(SCHEDULE, () => HttpResponse.json({ data: state.slots })),
    http.put(SCHEDULE, async ({ request }) => {
      const body = (await request.json()) as {
        slots: Omit<ReturnType<typeof scheduleSlot>, "id">[];
      };
      state.puts.push(body);
      if (putResponse) return putResponse();
      state.slots = body.slots.map((slot, index) => ({ ...slot, id: `n${index}` }));
      return HttpResponse.json({ data: state.slots });
    }),
  );
  return state;
}

const asManager = (permissions = MANAGER_PERMISSIONS) =>
  signedInBackend({
    me: meFixture({ role: "company_manager", permissions }),
    branches: [centro],
  });

const day = (name: string) => screen.getByRole("group", { name });
const setTime = (input: HTMLElement, value: string) =>
  fireEvent.change(input, { target: { value } });

describe("Horario de la sucursal", () => {
  it("sin franjas muestra el estado vacío 'Configure el horario…' junto al editor", async () => {
    asManager();
    scheduleBackend([]);
    await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    expect(
      await screen.findByRole("heading", {
        name: "Configure el horario: la sucursal está cerrada hasta entonces",
      }),
    ).toBeTruthy();
    expect(
      screen.getByRole("heading", { level: 1, name: "Horario de Sucursal Centro" }),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Guardar horario" })).toBeTruthy();
  });

  it("agrega una franja y guarda el horario completo por PUT", async () => {
    asManager();
    const backend = scheduleBackend([scheduleSlot("a", 1, "09:00", "13:00")]);
    const { user } = await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    await screen.findByRole("group", { name: "Lunes" });
    await user.click(within(day("Martes")).getByRole("button", { name: "Agregar franja" }));
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    await waitFor(() => expect(backend.puts).toHaveLength(1));
    expect(backend.puts[0]).toEqual({
      slots: [
        { weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00" },
        { weekday: 2, starts_at_local: "09:00", ends_at_local: "13:00" },
      ],
    });
  });

  it("AC3: un solape en el cliente marca el campo y NO se envía ninguna petición PUT", async () => {
    asManager();
    const backend = scheduleBackend([
      scheduleSlot("a", 1, "09:00", "13:00"),
      scheduleSlot("b", 1, "12:00", "15:00"),
    ]);
    const { user } = await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    await screen.findByRole("group", { name: "Lunes" });
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(within(day("Lunes")).getAllByRole("alert")).toHaveLength(2);
    expect(backend.puts).toHaveLength(0);
  });

  it("AC3: un 422 slots/overlap del servidor se muestra en el editor", async () => {
    asManager();
    scheduleBackend([scheduleSlot("a", 1, "09:00", "13:00")], () =>
      HttpResponse.json(validationProblem("slots", "overlap", "las franjas se solapan"), {
        status: 422,
      }),
    );
    const { user } = await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    await screen.findByRole("group", { name: "Lunes" });
    setTime(within(day("Lunes")).getByLabelText("Fin"), "14:00");
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect((await screen.findByRole("alert")).textContent).toContain("las franjas se solapan");
  });

  it("guardar sin franjas exige confirmar el cierre y entonces envía slots: []", async () => {
    asManager();
    const backend = scheduleBackend([scheduleSlot("a", 1, "09:00", "13:00")]);
    const { user } = await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    await screen.findByRole("group", { name: "Lunes" });
    await user.click(within(day("Lunes")).getByRole("button", { name: "Quitar franja" }));
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));
    expect(backend.puts).toHaveLength(0);
    await user.click(
      within(screen.getByRole("dialog")).getByRole("button", { name: "Dejar cerrada" }),
    );

    await waitFor(() => expect(backend.puts).toEqual([{ slots: [] }]));
  });

  it("sin appointments.schedule.manage el horario es de solo lectura (gate)", async () => {
    asManager(READER_PERMISSIONS);
    scheduleBackend([scheduleSlot("a", 1, "09:00", "13:00")]);
    await renderApp({ route: `/branches/${ids.branchA}/schedule` });

    expect(
      await within(await screen.findByRole("group", { name: "Lunes" })).findByText("9:00 a. m. – 1:00 p. m."),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Guardar horario" })).toBeNull();
    expect(screen.queryByLabelText("Inicio")).toBeNull();
  });

  it("una sucursal que no es de la empresa da 'no encontrada' y no pide su horario (adversarial)", async () => {
    asManager();
    scheduleBackend([]);
    await renderApp({ route: "/branches/0198f0a0-0000-7000-8000-0000000000ff/schedule" });

    expect(await screen.findByRole("heading", { name: "No encontramos esta página" })).toBeTruthy();
  });
});
