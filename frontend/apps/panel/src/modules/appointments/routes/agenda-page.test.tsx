import { focusManager } from "@tanstack/react-query";
import { cleanup, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  PROFESSIONAL_PERMISSIONS,
  RECEPTION_PERMISSIONS,
  agendaAppointment,
  agendaBackend,
} from "../../../test/agenda-backend";
import { branch, ids, meFixture } from "../../../test/fixtures";
import { pickDate } from "../../../test/date-time-fields";
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

  it("sin permiso para ver el nombre muestra el texto de respaldo y nunca el id del cliente", async () => {
    asReception();
    agendaBackend({
      appointments: [agendaAppointment({ customer_name: null, customer_id: "c-secreto" })],
    });
    await renderApp({ route });

    const card = await screen.findByRole("button", { name: /Cliente/ });
    expect(card.textContent).toContain("Cliente");
    expect(document.body.textContent).not.toContain("c-secreto");
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
  it("pide elegir la sucursal en el selector global y, al elegirla allí, carga su agenda", async () => {
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

    expect(await screen.findByRole("heading", { name: "Elija una sucursal" })).toBeTruthy();
    expect(screen.queryByRole("combobox")).toBeNull();
    await user.click(screen.getByRole("button", { name: /Cambiar el contexto de trabajo/ }));
    await user.click(await screen.findByRole("menuitemradio", { name: "Sucursal Norte" }));

    await waitFor(() => expect(seen).toContain(ids.branchA2));
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(0));
  });
});

describe("Agenda: panel flotante", () => {
  afterEach(() => Object.defineProperty(window, "innerWidth", { configurable: true, value: 1024 }));

  it("en pantalla ancha arranca sin panel: uno flotante no tapa la agenda sin que lo pidan", async () => {
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 1440 });
    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });

    const toggle = await screen.findByRole("button", { name: /Próximas llegadas/ });
    expect(await column("Rosa Martínez")).toBeTruthy();
    expect(screen.queryByRole("complementary", { name: "Próximas llegadas" })).toBeNull();
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
  });
});

describe("Agenda: filas, filtros y densidad", () => {
  afterEach(() => window.localStorage.clear());

  const chip = (name: RegExp) =>
    within(screen.getByRole("group", { name: "Filtrar por estado" })).getByRole("button", { name });

  it("apagar «Completada» quita esas citas y los contadores lo reflejan", async () => {
    asReception();
    agendaBackend({
      appointments: [
        agendaAppointment({ id: "a", status: "completed", customer_name: "Ana Ruiz" }),
        agendaAppointment({
          id: "b",
          status: "completed",
          customer_name: "Luz Mora",
          professional_id: "p2",
        }),
        agendaAppointment({
          id: "c",
          customer_name: "Eva Luna",
          starts_at: "2026-11-18T17:00:00.000Z",
          ends_at: "2026-11-18T17:45:00.000Z",
        }),
      ],
    });
    const { user } = await renderApp({ route });
    await screen.findByRole("button", { name: /Luz Mora/ });
    expect(chip(/^Todas/).textContent).toContain("3");
    expect(chip(/^Completada/).textContent).toContain("2");

    await user.click(chip(/^Completada/));

    await waitFor(() => expect(screen.queryByRole("button", { name: /Ana Ruiz/ })).toBeNull());
    expect(screen.queryByRole("button", { name: /Luz Mora/ })).toBeNull();
    expect(screen.getByRole("button", { name: /Eva Luna/ })).toBeTruthy();
    expect(chip(/^Completada/).getAttribute("aria-pressed")).toBe("false");
    expect(chip(/^Todas/).textContent).toContain("1");

    await user.click(chip(/^Todas/));
    expect(await screen.findByRole("button", { name: /Ana Ruiz/ })).toBeTruthy();
  });

  it("el título abre el calendario y lleva al día elegido", async () => {
    asReception();
    const backend = agendaBackend();
    const { user } = await renderApp({ route });
    const heading = await screen.findByRole("heading", {
      level: 1,
      name: /Agenda del miércoles 18 de noviembre/,
    });

    await pickDate(user, within(heading).getByRole("button"), "2026-11-20");

    await screen.findByRole("heading", { level: 1, name: /viernes 20 de noviembre/ });
    await waitFor(() => expect(backend.appointmentQueries.at(-1)?.get("from")).toBe("2026-11-20"));
  });

  it("la densidad compacta se recuerda al volver a la agenda", async () => {
    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    const first = await renderApp({ route });
    await screen.findByRole("button", { name: /Ana Ruiz/ });

    await first.user.click(screen.getByRole("button", { name: "Vista compacta" }));
    await waitFor(() =>
      expect(document.querySelector("[data-slot=agenda-view]")?.getAttribute("data-density")).toBe(
        "compact",
      ),
    );
    cleanup();

    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });
    await screen.findByRole("button", { name: /Ana Ruiz/ });
    expect(
      screen.getByRole("button", { name: "Vista compacta" }).getAttribute("aria-pressed"),
    ).toBe("true");
  });

  it("la agenda ocupa el alto de la hoja y desplaza solo su cuerpo", async () => {
    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });
    await screen.findByRole("button", { name: /Ana Ruiz/ });

    const view = document.querySelector("[data-slot=agenda-view]")!;
    expect(view.closest("[data-slot=page-body]")).toBeTruthy();
    expect(view.closest("[data-slot=page-frame]")).toBeTruthy();
  });
});

describe("Agenda: semana", () => {
  it("al elegir otro profesional muestra sus citas de lunes a domingo en columnas", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [
        agendaAppointment({ id: "rosa-mie", customer_name: "Ana Ruiz" }),
        agendaAppointment({
          id: "luis-vie",
          professional_id: "p2",
          customer_name: "Eva Luna",
          starts_at: "2026-11-20T16:00:00.000Z",
          ends_at: "2026-11-20T17:00:00.000Z",
        }),
        agendaAppointment({
          id: "luis-dom",
          professional_id: "p2",
          customer_name: "Raúl Mora",
          starts_at: "2026-11-22T15:00:00.000Z",
          ends_at: "2026-11-22T16:00:00.000Z",
        }),
      ],
    });
    const { user } = await renderApp({ route: `${route}&view=week` });
    await screen.findByRole("button", { name: /Ana Ruiz/ });

    await user.click(screen.getByRole("combobox", { name: "Profesional de la semana" }));
    await user.click(await screen.findByRole("option", { name: "Luis Pérez" }));

    expect(await screen.findByRole("button", { name: /Eva Luna/ })).toBeTruthy();
    expect(screen.getByRole("button", { name: /Raúl Mora/ })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /Ana Ruiz/ })).toBeNull();
    const query = backend.appointmentQueries.at(-1);
    expect([query?.get("from"), query?.get("to"), query?.get("professional_id")]).toEqual([
      "2026-11-16",
      "2026-11-22",
      "p2",
    ]);
    const days = screen
      .getAllByRole("columnheader")
      .map((item) => item.querySelector("time")?.getAttribute("datetime"));
    expect(days).toEqual([
      "2026-11-16",
      "2026-11-17",
      "2026-11-18",
      "2026-11-19",
      "2026-11-20",
      "2026-11-21",
      "2026-11-22",
    ]);
  });
});

describe("Agenda: celular", () => {
  afterEach(() => vi.restoreAllMocks());

  function narrowScreen() {
    vi.spyOn(window, "matchMedia").mockImplementation(
      (query: string) =>
        ({
          matches: query.includes("max-width"),
          media: query,
          onchange: null,
          addEventListener() {},
          removeEventListener() {},
          addListener() {},
          removeListener() {},
          dispatchEvent: () => false,
        }) as MediaQueryList,
    );
  }

  it("muestra la lista por profesional con un solo botón flotante de Nueva cita", async () => {
    narrowScreen();
    asReception();
    agendaBackend({ appointments: [agendaAppointment()] });
    await renderApp({ route });

    expect(await screen.findByRole("group", { name: "Profesional" })).toBeTruthy();
    expect(await screen.findByRole("button", { name: /Ana Ruiz/ })).toBeTruthy();
    expect(document.querySelector(".ec")).toBeNull();
    expect(screen.getAllByRole("button", { name: "Nueva cita" })).toHaveLength(1);
    expect(screen.queryByRole("group", { name: "Densidad" })).toBeNull();
  });

  const wednesdayHours = (id: string) => [
    { id, weekday: 3, starts_at_local: "09:00", ends_at_local: "17:00" },
  ];

  it("una cita oculta con los chips sigue ocupando su hueco", async () => {
    narrowScreen();
    asReception();
    agendaBackend({
      // 9:00 to 9:45 in Managua, Luis's.
      appointments: [agendaAppointment({ professional_id: "p2" })],
      branchSchedule: wednesdayHours("b"),
      professionalSchedules: { p2: wednesdayHours("l") },
    });
    const { user } = await renderApp({ route });
    const people = await screen.findByRole("group", { name: "Profesional" });
    await user.click(within(people).getByRole("button", { name: /Luis Pérez/ }));
    await screen.findAllByRole("button", { name: /^Libre/ });

    const filters = screen.getByRole("group", { name: "Filtrar por estado" });
    await user.click(within(filters).getByRole("button", { name: /^Confirmada/ }));

    await waitFor(() => expect(screen.queryByRole("button", { name: /Ana Ruiz/ })).toBeNull());
    const gaps = screen.getAllByRole("button", { name: /^Libre/ });
    expect(gaps[0]?.getAttribute("aria-label")).toContain("9:45");
  });

  it("en la vista por recurso los huecos se ven pero no abren una cita sin recurso", async () => {
    narrowScreen();
    asReception();
    agendaBackend({
      appointments: [agendaAppointment({ resource_id: "r1" })],
      branchSchedule: wednesdayHours("b"),
      resourceSchedules: { r1: wednesdayHours("r") },
    });
    await renderApp({ route: `${route}&view=resources` });

    expect(await screen.findByRole("button", { name: /Ana Ruiz/ })).toBeTruthy();
    expect((await screen.findAllByText(/^Libre/)).length).toBeGreaterThan(0);
    expect(screen.queryByRole("button", { name: /^Libre/ })).toBeNull();
  });

  it("tocar un hueco libre abre Nueva cita con ese profesional y esa hora", async () => {
    narrowScreen();
    asReception();
    const wednesday = (id: string) => [
      { id, weekday: 3, starts_at_local: "09:00", ends_at_local: "17:00" },
    ];
    agendaBackend({
      appointments: [agendaAppointment()],
      branchSchedule: wednesday("b"),
      professionalSchedules: { p2: wednesday("l") },
    });
    const { user } = await renderApp({ route });

    const people = await screen.findByRole("group", { name: "Profesional" });
    await user.click(within(people).getByRole("button", { name: /Luis Pérez/ }));
    const [first] = await screen.findAllByRole("button", { name: /^Libre/ });
    // His own hours, not the agenda's default ones.
    expect(first!.getAttribute("aria-label")).toContain("9:00");
    await user.click(first!);

    const panel = await screen.findByRole("complementary", { name: "Nueva cita" });
    expect(within(panel).getByRole("combobox", { name: "Profesional" }).textContent).toContain(
      "Luis Pérez",
    );
  });
});
