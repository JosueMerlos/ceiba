import { focusManager } from "@tanstack/react-query";
import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import {
  PROFESSIONAL_PERMISSIONS,
  RECEPTION_PERMISSIONS,
  agendaAppointment,
  agendaBackend,
} from "../../../test/agenda-backend";
import { branch, ids, meFixture } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { signedInBackend } from "../../../test/server";
import { todayInZone } from "../lib/agenda-time";

const DAY = "2026-11-18";
const route = `/agenda?date=${DAY}`;
const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const norte = branch(ids.branchA2, ids.companyA, "Sucursal Norte");

const asReception = () =>
  signedInBackend({
    me: meFixture({ role: "receptionist", permissions: RECEPTION_PERMISSIONS }),
    branches: [centro],
  });

const asProfessional = () =>
  signedInBackend({
    me: meFixture({ role: "professional", permissions: PROFESSIONAL_PERMISSIONS }),
    branches: [centro],
  });

const column = (name: string) => screen.findByRole("group", { name });

afterEach(() => focusManager.setFocused(undefined));

describe("Agenda: recepción", () => {
  it("muestra el día por profesional con la cita en la hora de la sucursal", async () => {
    asReception();
    const backend = agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: /Agenda del miércoles 18 de noviembre/,
      }),
    ).toBeTruthy();
    expect(await column("Rosa Martínez")).toBeTruthy();
    expect(await column("Luis Pérez")).toBeTruthy();
    const card = await screen.findByRole("button", { name: /Ana Ruiz/ });
    expect(card.textContent).toContain("Corte de dama");
    expect(card.textContent).toContain("9:00");
    expect(card.textContent).toContain("Confirmada");
    expect(backend.appointmentQueries[0]?.get("from")).toBe(DAY);
    expect(backend.appointmentQueries[0]?.get("to")).toBe(DAY);
  });

  it("no dibuja las citas canceladas ni reprogramadas", async () => {
    asReception();
    agendaBackend({
      appointments: [
        agendaAppointment({ id: "viva", customer_name: "Ana Ruiz" }),
        agendaAppointment({ id: "x", customer_name: "Eva Cancelada", status: "cancelled" }),
        agendaAppointment({ id: "y", customer_name: "Raúl Movido", status: "rescheduled" }),
      ],
    });
    await renderApp({ route });

    await screen.findByRole("button", { name: /Ana Ruiz/ });
    expect(screen.queryByRole("button", { name: /Eva Cancelada/ })).toBeNull();
    expect(screen.queryByRole("button", { name: /Raúl Movido/ })).toBeNull();
  });

  it("resume las citas del día y cuántas faltan por confirmar", async () => {
    asReception();
    agendaBackend({
      appointments: [
        agendaAppointment({ id: "a", status: "scheduled" }),
        agendaAppointment({ id: "b", professional_id: "p2" }),
        agendaAppointment({ id: "c", status: "cancelled" }),
      ],
    });
    await renderApp({ route });

    expect(await screen.findByText("2 citas, 1 por confirmar")).toBeTruthy();
  });

  it("un servicio archivado conserva su nombre y uno desconocido usa el texto de respaldo", async () => {
    asReception();
    agendaBackend({
      archivedServices: [{ id: "viejo", name: "Tinte antiguo" }],
      appointments: [
        agendaAppointment({
          id: "a",
          services: [
            {
              service_id: "viejo",
              position: 0,
              duration_minutes: 45,
              price_minor: 1,
              currency: "NIO",
            },
          ],
        }),
        agendaAppointment({
          id: "b",
          professional_id: "p2",
          customer_name: "Luz Mora",
          services: [
            {
              service_id: "nadie",
              position: 0,
              duration_minutes: 45,
              price_minor: 1,
              currency: "NIO",
            },
          ],
        }),
      ],
    });
    await renderApp({ route });

    await waitFor(() =>
      expect(screen.getByRole("button", { name: /Ana Ruiz/ }).textContent).toContain(
        "Tinte antiguo",
      ),
    );
    expect(screen.getByRole("button", { name: /Luz Mora/ }).textContent).toContain("Servicio");
  });

  it("sombrea lo cerrado cuando llegan los horarios, sin bloquear la primera pintura", async () => {
    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });

    await screen.findByRole("button", { name: /Ana Ruiz/ });
    // The demo backend gives nobody hours of their own, so both columns end up closed.
    await waitFor(() => expect(document.querySelector(".agenda-block")).not.toBeNull());
  });

  it("cambia de día y pide el rango nuevo", async () => {
    asReception();
    const backend = agendaBackend();
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Día siguiente" }));

    await screen.findByRole("heading", { level: 1, name: /jueves 19 de noviembre/ });
    await waitFor(() => expect(backend.appointmentQueries.at(-1)?.get("from")).toBe("2026-11-19"));
  });

  it("la vista por recurso agrupa por recurso y reúne lo que no usa ninguno", async () => {
    asReception();
    agendaBackend({
      appointments: [
        agendaAppointment({ id: "a", resource_id: "r1" }),
        agendaAppointment({ id: "b", resource_id: null, customer_name: "Luz Mora" }),
      ],
    });
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Por recurso" }));

    expect(await column("Sillón 1")).toBeTruthy();
    expect(await column("Sin recurso")).toBeTruthy();
    expect(screen.queryByRole("group", { name: "Rosa Martínez" })).toBeNull();
  });

  it("la semana pide de lunes a domingo para un profesional", async () => {
    asReception();
    const backend = agendaBackend();
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Semana" }));

    await screen.findByRole("heading", { level: 1, name: /semana del 16 de noviembre/ });
    await waitFor(() => {
      const query = backend.appointmentQueries.at(-1);
      expect([query?.get("from"), query?.get("to"), query?.get("professional_id")]).toEqual([
        "2026-11-16",
        "2026-11-22",
        "p1",
      ]);
    });
  });

  it("la semana solo carga los horarios del profesional elegido", async () => {
    asReception();
    const backend = agendaBackend();
    await renderApp({ route: `${route}&view=week` });

    await waitFor(() => expect(backend.scheduleOwners).toContain("p1"));
    expect(backend.scheduleOwners).not.toContain("p2");
  });

  it("la semana sin profesionales asignados lo explica en vez de quedarse cargando", async () => {
    asReception();
    agendaBackend({ professionals: [] });
    await renderApp({ route: `${route}&view=week` });

    expect(await screen.findByText("No hay profesionales asignados a esta sucursal.")).toBeTruthy();
  });

  it("una fecha imposible en la URL abre el día de hoy", async () => {
    asReception();
    const backend = agendaBackend();
    await renderApp({ route: "/agenda?date=2026-13-45" });

    await screen.findByRole("heading", { level: 1, name: /Agenda del/ });
    await waitFor(() =>
      expect(backend.appointmentQueries[0]?.get("from")).toBe(todayInZone("America/Managua")),
    );
  });

  it("se refresca cada 30 s y al volver a enfocar la ventana", async () => {
    asReception();
    const backend = agendaBackend();
    const { app } = await renderApp({ route });
    await column("Rosa Martínez");

    const query = app.queryClient
      .getQueryCache()
      .getAll()
      .find((item) => item.queryKey[0] === "agenda" && item.queryKey[1] === "appointments");
    expect(query?.observers[0]?.options.refetchInterval).toBe(30_000);

    const before = backend.appointmentQueries.length;
    focusManager.setFocused(false);
    focusManager.setFocused(true);
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(before));
  });

  it("el panel de próximas llegadas lista quién llega en la próxima hora", async () => {
    asReception();
    const soon = new Date(Date.now() + 10 * 60_000).toISOString();
    agendaBackend({ appointments: [agendaAppointment({ starts_at: soon, status: "scheduled" })] });
    const { user } = await renderApp({
      route: `/agenda?date=${todayInZone("America/Managua")}`,
    });

    await user.click(await screen.findByRole("button", { name: /Próximas llegadas/ }));

    const panel = await screen.findByRole("complementary", { name: "Próximas llegadas" });
    expect(within(panel).getByText("Ana Ruiz")).toBeTruthy();
    expect(within(panel).getByText("Por confirmar")).toBeTruthy();
    expect(within(panel).getByText(/Corte de dama con Rosa Martínez/)).toBeTruthy();
  });
});

describe("Agenda: profesional", () => {
  it("ve solo su columna, sin pedir el listado de profesionales ni ofrecer Nueva cita", async () => {
    asProfessional();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      professionalsForbidden: true,
      profiles: { p1: "Rosa Martínez" },
    });
    await renderApp({ route });

    expect(await column("Rosa Martínez")).toBeTruthy();
    await screen.findByRole("button", { name: /Ana Ruiz/ });
    expect(screen.queryByRole("button", { name: "Nueva cita" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Por recurso" })).toBeNull();
    expect(backend.professionalListCalls).toBe(0);
  });

  it("la vista por recurso en la URL no se aplica a quien no puede usarla", async () => {
    asProfessional();
    agendaBackend({
      appointments: [agendaAppointment()],
      professionalsForbidden: true,
      profiles: { p1: "Rosa Martínez" },
    });
    await renderApp({ route: `${route}&view=resources` });

    expect(await column("Rosa Martínez")).toBeTruthy();
    expect(screen.queryByRole("group", { name: "Sin recurso" })).toBeNull();
  });

  it("sin citas ese día ve un aviso y no una pantalla de error", async () => {
    asProfessional();
    agendaBackend({ professionalsForbidden: true });
    await renderApp({ route });

    expect(await screen.findByText("No tiene citas este día.")).toBeTruthy();
    expect(screen.getAllByRole("heading", { name: /Agenda/ })).toHaveLength(1);
  });
});

describe("Agenda: sin sucursal en el contexto", () => {
  it("al elegir sucursal cambia el contexto y carga su agenda", async () => {
    const seen: (string | null)[] = [];
    signedInBackend({
      me: (query) => {
        const branchId = query.get("branch_id");
        seen.push(branchId);
        return meFixture({
          role: "company_manager",
          permissions: RECEPTION_PERMISSIONS,
          branch: branchId === ids.branchA2 ? norte : null,
        });
      },
      branches: [centro, norte],
    });
    const backend = agendaBackend({ branchId: ids.branchA2 });
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("combobox", { name: "Sucursal de trabajo" }));
    await user.click(await screen.findByRole("option", { name: "Sucursal Norte" }));

    await waitFor(() => expect(seen).toContain(ids.branchA2));
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(0));
  });
});
