import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import {
  PROFESSIONAL_PERMISSIONS,
  RECEPTION_PERMISSIONS,
  agendaAppointment,
  agendaBackend,
} from "../../../test/agenda-backend";
import { branch, ids, meFixture } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { signedInBackend } from "../../../test/server";

const route = "/agenda?date=2026-11-18";
const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const CONFLICT = { status: 409, code: "appointments.slot_unavailable" };
const slot = {
  professional_id: "p1",
  resource_id: null,
  starts_at: "2026-11-18T16:00:00.000Z",
  ends_at: "2026-11-18T16:45:00.000Z",
};
const ana = { id: "c1", full_name: "Ana Ruiz", phone_e164: "+50588887777" };

const asReception = () =>
  signedInBackend({
    me: meFixture({ role: "receptionist", permissions: RECEPTION_PERMISSIONS }),
    branches: [centro],
  });
const detail = (overrides = {}) => ({ ...agendaAppointment(overrides), notes: null });

type User = Awaited<ReturnType<typeof renderApp>>["user"];

async function fillNewAppointment(user: User) {
  await user.click(await screen.findByRole("button", { name: "Nueva cita" }));
  const panel = await screen.findByRole("complementary", { name: "Nueva cita" });
  await user.click(await within(panel).findByRole("checkbox", { name: "Corte de dama" }));
  await user.click(await within(panel).findByRole("button", { name: /10:00/ }));
  await user.type(within(panel).getByLabelText("Buscar cliente"), "Ana");
  await user.click(await within(panel).findByRole("button", { name: /Ana Ruiz/ }));
  return panel;
}

// A plain click: the calendar tracks pointer gestures with layout that jsdom does not have. It reports the click from
// outside React, so the test yields to the scheduler before looking for the panel.
async function openDetail(name: RegExp = /Ana Ruiz/) {
  fireEvent.click(await screen.findByRole("button", { name }));
  await new Promise((resolve) => setTimeout(resolve, 50));
  return screen.findByRole("complementary", { name: "Ana Ruiz" });
}

describe("Crear una cita", () => {
  it("envía servicios, cliente, profesional, hora en UTC e Idempotency-Key", async () => {
    asReception();
    const backend = agendaBackend({ availability: [slot], customers: [ana] });
    const { user } = await renderApp({ route });

    const panel = await fillNewAppointment(user);
    const before = backend.appointmentQueries.length;
    await user.click(within(panel).getByRole("button", { name: "Confirmar cita" }));

    await waitFor(() => expect(backend.writes).toHaveLength(1));
    expect(backend.writes[0]).toMatchObject({
      action: "book",
      body: {
        customer_id: "c1",
        service_ids: ["s1"],
        professional_id: "p1",
        starts_at: "2026-11-18T16:00:00.000Z",
      },
    });
    expect(backend.writes[0]?.key).toBeTruthy();
    expect(backend.availabilityQueries[0]?.get("service_ids")).toBe("s1");
    expect(backend.availabilityQueries[0]?.get("professional_id")).toBe("p1");
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(before));
    await waitFor(() =>
      expect(screen.queryByRole("complementary", { name: "Nueva cita" })).toBeNull(),
    );
  });

  it("si otra persona ganó el hueco avisa, refresca y conserva el formulario", async () => {
    asReception();
    const backend = agendaBackend({
      availability: [slot],
      customers: [ana],
      writeFailure: CONFLICT,
    });
    const { user } = await renderApp({ route });

    const panel = await fillNewAppointment(user);
    const before = backend.appointmentQueries.length;
    await user.click(within(panel).getByRole("button", { name: "Confirmar cita" }));

    // Toasts outlive a test, so an earlier one may still be on screen.
    expect((await screen.findAllByText(/El horario ya no está disponible/)).length).toBeGreaterThan(
      0,
    );
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(before));
    expect(screen.getByRole("complementary", { name: "Nueva cita" })).toBeTruthy();
  });

  it("reintentar sin cambios reutiliza la clave para no duplicar la cita", async () => {
    asReception();
    const backend = agendaBackend({
      availability: [slot],
      customers: [ana],
      writeFailure: { status: 500, code: "internal.error" },
    });
    const { user } = await renderApp({ route });

    const panel = await fillNewAppointment(user);
    const confirm = within(panel).getByRole("button", { name: "Confirmar cita" });
    await user.click(confirm);
    await waitFor(() => expect(backend.writes).toHaveLength(1));
    await waitFor(() => expect(confirm.hasAttribute("disabled")).toBe(false));
    await user.click(confirm);

    await waitFor(() => expect(backend.writes).toHaveLength(2));
    expect(backend.writes[1]?.key).toBe(backend.writes[0]?.key);
  });

  it("crea un cliente nuevo y lo deja seleccionado", async () => {
    asReception();
    const backend = agendaBackend({ availability: [slot] });
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Nueva cita" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva cita" });
    await user.type(await within(panel).findByLabelText("Buscar cliente"), "Eva");
    await user.click(await within(panel).findByRole("button", { name: "Crear cliente" }));
    await user.type(within(panel).getByLabelText("Nombre completo"), "Eva Luna");
    await user.type(within(panel).getByLabelText("Teléfono"), "88881234");
    await user.click(within(panel).getByRole("button", { name: "Guardar cliente" }));

    await waitFor(() =>
      expect(backend.createdCustomers).toEqual([{ full_name: "Eva Luna", phone_e164: "88881234" }]),
    );
    expect(await within(panel).findByText("Eva Luna")).toBeTruthy();
  });

  it("los profesionales pausados no se ofrecen para reservar", async () => {
    asReception();
    agendaBackend({
      professionals: [
        {
          id: "p1",
          display_name: "Rosa Martínez",
          branch_ids: [ids.branchA],
          service_ids: ["s1"],
          active: false,
        },
        { id: "p2", display_name: "Luis Pérez", branch_ids: [ids.branchA], service_ids: ["s1"] },
      ],
    });
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Nueva cita" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva cita" });
    const picker = within(panel).getByRole("combobox", { name: "Profesional" });
    expect(picker.textContent).toContain("Luis Pérez");
    await user.click(picker);

    expect(await screen.findByRole("option", { name: "Luis Pérez" })).toBeTruthy();
    expect(screen.queryByRole("option", { name: "Rosa Martínez" })).toBeNull();
  });

  it("desde la semana de un profesional, Nueva cita lo propone a él", async () => {
    asReception();
    agendaBackend();
    const { user } = await renderApp({ route: `${route}&view=week&pro=p2` });

    await user.click(await screen.findByRole("button", { name: "Nueva cita" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva cita" });

    expect(within(panel).getByRole("combobox", { name: "Profesional" }).textContent).toContain(
      "Luis Pérez",
    );
  });

  it("busca por teléfono cuando se escriben dígitos", async () => {
    asReception();
    const backend = agendaBackend({ customers: [ana] });
    const { user } = await renderApp({ route });

    await user.click(await screen.findByRole("button", { name: "Nueva cita" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva cita" });
    await user.type(await within(panel).findByLabelText("Buscar cliente"), "8888-7777");

    await waitFor(() => expect(backend.customerQueries.at(-1)?.get("phone")).toBe("8888-7777"));
  });
});

describe("Próximas llegadas", () => {
  it("a quien llegó tarde sin confirmar se le marca la llegada directamente", async () => {
    asReception();
    const late = new Date(Date.now() - 10 * 60_000).toISOString();
    const backend = agendaBackend({
      appointments: [agendaAppointment({ starts_at: late, status: "scheduled" })],
    });
    const { user } = await renderApp({
      route: `/agenda?date=${new Date().toLocaleDateString("en-CA", { timeZone: "America/Managua" })}`,
    });

    await user.click(await screen.findByRole("button", { name: /Próximas llegadas/ }));
    const panel = await screen.findByRole("complementary", { name: "Próximas llegadas" });
    await user.click(await within(panel).findByRole("button", { name: "Marcar llegada" }));

    await waitFor(() => expect(backend.writes[0]).toMatchObject({ action: "check_in" }));
  });
});

describe("Detalle y estados", () => {
  it("recepción marca la llegada y la agenda se actualiza", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    const before = backend.appointmentQueries.length;
    await user.click(await within(panel).findByRole("button", { name: "Marcar llegada" }));

    await waitFor(() =>
      expect(backend.writes[0]).toMatchObject({ action: "check_in", id: "cita-1" }),
    );
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(before));
  });

  it("cancelar exige un motivo y lo envía como código", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.click(await within(panel).findByRole("button", { name: "Cancelar cita" }));
    const confirm = within(panel).getByRole("button", { name: "Confirmar cancelación" });
    expect(confirm.hasAttribute("disabled")).toBe(true);
    await user.click(within(panel).getByRole("combobox", { name: "Motivo" }));
    await user.click(await screen.findByRole("option", { name: "Lo pidió el cliente" }));
    await user.click(confirm);

    await waitFor(() =>
      expect(backend.writes[0]).toMatchObject({
        action: "cancel",
        body: { reason: "customer_request" },
      }),
    );
  });

  it("el profesional no ve cancelar ni reprogramar", async () => {
    signedInBackend({
      me: meFixture({ role: "professional", permissions: PROFESSIONAL_PERMISSIONS }),
      branches: [centro],
    });
    agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      professionalsForbidden: true,
      profiles: { p1: "Rosa Martínez" },
    });
    await renderApp({ route });

    const panel = await openDetail();

    expect(await within(panel).findByRole("button", { name: "Marcar llegada" })).toBeTruthy();
    expect(within(panel).queryByRole("button", { name: "Cancelar cita" })).toBeNull();
    expect(within(panel).queryByRole("button", { name: "Reprogramar" })).toBeNull();
  });

  it("mover por formulario llama a reprogramar con su clave", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      availability: [slot],
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.click(await within(panel).findByRole("button", { name: "Reprogramar" }));
    await user.click(await within(panel).findByRole("button", { name: /10:00/ }));
    await user.click(within(panel).getByRole("button", { name: "Mover cita" }));

    await waitFor(() =>
      expect(backend.writes[0]).toMatchObject({
        action: "reschedule",
        id: "cita-1",
        body: { starts_at: "2026-11-18T16:00:00.000Z", professional_id: "p1" },
      }),
    );
    expect(backend.writes[0]?.key).toBeTruthy();
  });

  it("reprogramar solo ofrece los inicios que la disponibilidad da por libres", async () => {
    asReception();
    agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      availability: [slot],
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.click(await within(panel).findByRole("button", { name: "Reprogramar" }));
    await within(panel).findByRole("button", { name: /10:00/ });

    // The appointment runs 9:00 to 9:45: starts over itself are not free, so they are not offered.
    const times = within(panel)
      .getAllByRole("button", { pressed: false })
      .map((button) => button.textContent)
      .filter((text) => /\d:\d\d/.test(text ?? ""));
    expect(times).toEqual(["10:00\u00a0a.\u00a0m."]);
  });

  it("un conflicto al mover avisa y refresca la agenda", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      availability: [slot],
      writeFailure: CONFLICT,
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.click(await within(panel).findByRole("button", { name: "Reprogramar" }));
    await user.click(await within(panel).findByRole("button", { name: /10:00/ }));
    const before = backend.appointmentQueries.length;
    await user.click(within(panel).getByRole("button", { name: "Mover cita" }));

    // Toasts outlive a test, so an earlier one may still be on screen.
    expect((await screen.findAllByText(/El horario ya no está disponible/)).length).toBeGreaterThan(
      0,
    );
    await waitFor(() => expect(backend.appointmentQueries.length).toBeGreaterThan(before));
  });

  it("muestra de dónde viene una cita reprogramada", async () => {
    asReception();
    const moved = agendaAppointment({ rescheduled_from_id: "origen" });
    const origin = detail({
      id: "origen",
      status: "rescheduled",
      starts_at: "2026-11-17T15:00:00.000Z",
    });
    agendaBackend({
      appointments: [moved],
      details: { "cita-1": { ...moved, notes: null }, origen: origin },
    });
    await renderApp({ route });

    const panel = await openDetail();

    expect(await within(panel).findByText(/Reprogramada desde/)).toBeTruthy();
    expect(within(panel).getByText(/mar\s17\snov\s2026/)).toBeTruthy();
  });

  it("si no puede leer la cita de origen, el detalle sigue funcionando", async () => {
    asReception();
    const moved = agendaAppointment({ rescheduled_from_id: "ajena" });
    agendaBackend({ appointments: [moved], details: { "cita-1": { ...moved, notes: null } } });
    await renderApp({ route });

    const panel = await openDetail();

    expect(await within(panel).findByRole("button", { name: "Marcar llegada" })).toBeTruthy();
    expect(within(panel).queryByText(/Reprogramada desde/)).toBeNull();
  });

  it("las notas sin guardar sobreviven a un cambio de estado de la cita", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.type(await within(panel).findByLabelText("Notas"), "Trae su propio tinte");
    const readsBefore = backend.detailReads;
    await user.click(within(panel).getByRole("button", { name: "Marcar llegada" }));
    await waitFor(() => expect(backend.detailReads).toBeGreaterThan(readsBefore));

    expect((within(panel).getByLabelText("Notas") as HTMLTextAreaElement).value).toBe(
      "Trae su propio tinte",
    );
    await user.click(within(panel).getByRole("button", { name: "Guardar notas" }));
    await waitFor(() => expect(backend.writes.at(-1)?.action).toBe("notes"));
    expect(backend.writes.at(-1)?.body).toEqual({ notes: "Trae su propio tinte", lock_version: 1 });
  });

  it("si otra persona guardó otras notas, muestra las suyas y no las pisa sin que se elija", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      notesSavedByOther: "Pagó por adelantado",
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.type(await within(panel).findByLabelText("Notas"), "Alérgica al amoníaco");
    await user.click(within(panel).getByRole("button", { name: "Guardar notas" }));

    expect(await within(panel).findByText(/Pagó por adelantado/)).toBeTruthy();
    expect(
      within(panel).getByRole("button", { name: "Guardar notas" }).hasAttribute("disabled"),
    ).toBe(true);
    expect((within(panel).getByLabelText("Notas") as HTMLTextAreaElement).value).toBe(
      "Alérgica al amoníaco",
    );

    await user.click(within(panel).getByRole("button", { name: "Reemplazar con mi nota" }));
    await user.click(within(panel).getByRole("button", { name: "Guardar notas" }));
    await waitFor(() => expect(backend.writes).toHaveLength(2));
    expect(backend.writes[1]?.body).toEqual({ notes: "Alérgica al amoníaco", lock_version: 1 });
  });

  it("no se puede escribir mientras se guardan las notas, así nada tecleado se pierde", async () => {
    asReception();
    const backend = agendaBackend({
      appointments: [agendaAppointment()],
      details: { "cita-1": detail() },
      notesDelayMs: 300,
    });
    const { user } = await renderApp({ route });

    const panel = await openDetail();
    await user.type(await within(panel).findByLabelText("Notas"), "Primera visita");
    await user.click(within(panel).getByRole("button", { name: "Guardar notas" }));

    await waitFor(() => expect(backend.writes).toHaveLength(1));
    expect(within(panel).getByLabelText("Notas").hasAttribute("disabled")).toBe(true);
  });
});
