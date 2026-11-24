import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { servicesBackend } from "../../../test/catalog-backend";
import {
  branch,
  ids,
  meFixture,
  professional,
  scheduleSlot,
  service,
  timeOff,
} from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { fillWallClock } from "../../../test/date-time-fields";
import { signedInBackend } from "../../../test/server";
import {
  STAFF_MANAGER_PERMISSIONS,
  STAFF_READER_PERMISSIONS,
  staffBackend,
} from "../../../test/staff-backend";

const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const norte = branch(ids.branchA2, ids.companyA, "Sucursal Norte");

const corte = service("s1", "Corte clásico");
const barba = service("s2", "Barba");

const efrain = professional("p1", "Don Efraín", {
  branch_ids: [ids.branchA],
  service_ids: ["s1"],
});
const sandra = professional("p2", "Sandra Gómez", { branch_ids: [], service_ids: [] });

/** The company manager works at company level (no branch in the context). */
const asCompanyManager = (permissions = STAFF_MANAGER_PERMISSIONS) =>
  signedInBackend({
    me: meFixture({ role: "company_manager", permissions, branch: null }),
    branches: [centro],
  });

/** A branch manager has the branch in the context: company-scope routes are not theirs. */
const asBranchManager = (permissions = STAFF_MANAGER_PERMISSIONS) =>
  signedInBackend({
    me: meFixture({ role: "receptionist", permissions, branch: centro }),
    branches: [centro],
  });

async function openProfessionals() {
  const view = await renderApp({ route: "/professionals" });
  await screen.findByRole("heading", { level: 1, name: "Profesionales" });
  return view;
}

async function openPanel(
  user: Awaited<ReturnType<typeof openProfessionals>>["user"],
  name: string,
) {
  await user.click(await screen.findByRole("button", { name: `Editar ${name}` }));
  return screen.findByRole("complementary", { name });
}

describe("Profesionales: lista y gates", () => {
  it("sin profesionales muestra 'Agregue su primer profesional' con la acción si hay professional.manage", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend();
    const { user } = await openProfessionals();

    expect(
      await screen.findByRole("heading", { name: "Agregue su primer profesional" }),
    ).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar profesional" }));
    expect(await screen.findByRole("complementary", { name: "Nuevo profesional" })).toBeTruthy();
  });

  it("sin professional.manage el estado vacío no ofrece acción ni 'Nuevo profesional' (gate)", async () => {
    asCompanyManager(STAFF_READER_PERMISSIONS);
    servicesBackend();
    staffBackend();
    await openProfessionals();

    expect(
      await screen.findByRole("heading", { name: "Agregue su primer profesional" }),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Agregar profesional" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Nuevo profesional" })).toBeNull();
  });

  it("la tabla muestra nombre, estado, nombres de sucursal y cantidad de servicios", async () => {
    asCompanyManager();
    servicesBackend({ services: [corte, barba] });
    staffBackend({
      professionals: [efrain, professional("p3", "Julio Pérez", { active: false })],
    });
    await openProfessionals();

    const row = (await screen.findByText("Don Efraín")).closest("tr")!;
    expect(within(row).getByText("Sucursal Centro")).toBeTruthy();
    expect(within(row).getByText("1 servicio")).toBeTruthy();
    expect(within(row).getByText("Activo")).toBeTruthy();
    const paused = screen.getByText("Julio Pérez").closest("tr")!;
    expect(within(paused).getByText("Pausado")).toBeTruthy();
    expect(within(paused).getByText("Sin sucursal")).toBeTruthy();
  });

  it("archiva desde la tabla con DELETE y desaparece de la lista; sin manage no hay Archivar (gate)", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    await user.click(await screen.findByRole("button", { name: "Archivar Don Efraín" }));
    await waitFor(() => expect(backend.archivedProfessionals).toEqual(["p1"]));
    await waitFor(() => expect(screen.queryByText("Don Efraín")).toBeNull());
  });

  it("recepción (AC8): sin crear ni acciones; la fila abre el detalle flotante de lectura, sin formularios ni modal", async () => {
    signedInBackend({
      me: meFixture({
        role: "receptionist",
        permissions: STAFF_READER_PERMISSIONS,
        branch: centro,
      }),
      branches: [centro],
    });
    servicesBackend({ services: [corte, barba] });
    staffBackend({
      professionals: [efrain],
      schedules: { p1: [scheduleSlot("sl1", 1, "08:00", "12:00")] },
    });
    const { user } = await openProfessionals();

    expect(await screen.findByText("Don Efraín")).toBeTruthy();
    expect(screen.getByText("Solo lectura")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Nuevo profesional" })).toBeNull();
    expect(screen.queryByRole("columnheader", { name: "Acciones" })).toBeNull();
    expect(screen.queryByRole("button", { name: /Archivar/ })).toBeNull();

    await user.click(screen.getByRole("button", { name: "Ver Don Efraín" }));
    const panel = await screen.findByRole("complementary", { name: "Don Efraín" });
    expect(panel.closest("[data-variant=floating]")).not.toBeNull();
    expect(await within(panel).findByText("Corte clásico")).toBeTruthy();
    expect(within(panel).getByText("Sucursal Centro")).toBeTruthy();
    const schedule = await within(panel).findByRole("region", { name: "Horario semanal" });
    expect(await within(schedule).findByText("8:00 a. m. – 12:00 p. m.")).toBeTruthy();
    expect(within(panel).queryByRole("textbox")).toBeNull();
    expect(within(panel).queryByRole("checkbox")).toBeNull();
    expect(within(panel).queryByRole("button", { name: /Guardar|Agregar/ })).toBeNull();
    expect(document.querySelectorAll("[data-slot=form-description]")).toHaveLength(0);
    expect(within(panel).queryByText(/Todo se guarda en la hora/)).toBeNull();
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("Profesionales: panel contextual", () => {
  it("edita el nombre y el estado por PATCH", async () => {
    asCompanyManager();
    servicesBackend({ services: [corte] });
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const name = within(panel).getByLabelText("Nombre para mostrar");
    await user.clear(name);
    await user.type(name, "Don Efraín B.");
    await user.click(within(panel).getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(backend.patchedProfessionals).toHaveLength(1));
    expect(backend.patchedProfessionals[0]).toEqual({
      id: "p1",
      body: { display_name: "Don Efraín B.", active: true },
    });
  });

  it("crea un profesional y queda en la lista", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    await user.click(await screen.findByRole("button", { name: "Nuevo profesional" }));
    const panel = await screen.findByRole("complementary", { name: "Nuevo profesional" });
    await user.type(within(panel).getByLabelText("Nombre para mostrar"), "Marlon Ruiz");
    await user.click(within(panel).getByRole("button", { name: "Crear profesional" }));

    await waitFor(() =>
      expect(backend.createdProfessionals).toEqual([{ display_name: "Marlon Ruiz", active: true }]),
    );
    expect(await screen.findByRole("button", { name: "Editar Marlon Ruiz" })).toBeTruthy();
  });

  it("servicios que presta: marca y guarda con PUT services", async () => {
    asCompanyManager();
    servicesBackend({ services: [corte, barba] });
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Servicios que presta" });
    await user.click(await within(section).findByRole("checkbox", { name: "Barba" }));
    await user.click(within(section).getByRole("button", { name: "Guardar servicios" }));

    await waitFor(() => expect(backend.servicePuts).toHaveLength(1));
    expect(backend.servicePuts[0]).toEqual({ id: "p1", body: { service_ids: ["s1", "s2"] } });
  });

  it("sucursales: asignar un profesional que ya tiene sucursales va directo, sin diálogo", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [centro, norte],
    });
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Sucursales" });
    await user.click(within(section).getByRole("checkbox", { name: "Sucursal Norte" }));

    await waitFor(() =>
      expect(backend.assignments).toEqual([{ branchId: ids.branchA2, professionalId: "p1" }]),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("sucursales: desmarcar una asignada hace DELETE assignment", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Sucursales" });
    await user.click(within(section).getByRole("checkbox", { name: "Sucursal Centro" }));

    await waitFor(() =>
      expect(backend.unassignments).toEqual([{ branchId: ids.branchA, professionalId: "p1" }]),
    );
  });

  it("sin professional.assign las sucursales quedan de solo lectura (gate)", async () => {
    asCompanyManager(
      STAFF_MANAGER_PERMISSIONS.filter((item) => item !== "appointments.professional.assign"),
    );
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Sucursales" });
    expect(within(section).getByRole("checkbox", { name: "Sucursal Centro" })).toHaveProperty(
      "disabled",
      true,
    );
  });
});

describe("Profesionales: horario por sucursal", () => {
  it("edita el horario de la sucursal de trabajo y guarda con PUT", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({
      professionals: [efrain],
      schedules: { p1: [scheduleSlot("sl1", 1, "08:00", "12:00")] },
    });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Horario semanal" });
    const monday = await within(section).findByRole("group", { name: "Lunes" });
    await user.click(within(monday).getByRole("button", { name: "Agregar franja" }));
    await user.click(within(section).getByRole("button", { name: "Guardar horario" }));

    await waitFor(() => expect(backend.schedulePuts).toHaveLength(1));
    expect(backend.schedulePuts[0]!.owner).toBe("p1");
    expect(backend.schedulePuts[0]!.body).toEqual({
      slots: [
        { weekday: 1, starts_at_local: "08:00", ends_at_local: "12:00" },
        { weekday: 1, starts_at_local: "12:00", ends_at_local: "16:00" },
      ],
    });
  });

  it("si el profesional no está asignado a la sucursal de trabajo pide asignarlo y no carga horario ni ausencias", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({ professionals: [sandra] });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    expect(await within(panel).findByText(/Asígnelo a Sucursal Centro/)).toBeTruthy();
    expect(within(panel).queryByRole("region", { name: "Horario semanal" })).toBeNull();
    expect(within(panel).queryByRole("region", { name: "Ausencias" })).toBeNull();
  });

  it("un 422 por cruce con otra sucursal se muestra en el editor", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({
      professionals: [efrain],
      schedules: { p1: [scheduleSlot("sl1", 1, "08:00", "12:00")] },
      scheduleOverlap: true,
    });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Horario semanal" });
    await within(section).findByRole("group", { name: "Lunes" });
    await user.click(within(section).getByRole("button", { name: "Guardar horario" }));

    expect(
      await within(section).findByText(/Se cruza con el horario en otra sucursal/),
    ).toBeTruthy();
  });

  it("sin schedule.manage el horario es de solo lectura (gate)", async () => {
    asCompanyManager(
      STAFF_MANAGER_PERMISSIONS.filter((item) => item !== "appointments.schedule.manage"),
    );
    servicesBackend();
    staffBackend({
      professionals: [efrain],
      schedules: { p1: [scheduleSlot("sl1", 1, "08:00", "12:00")] },
    });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Horario semanal" });
    expect(await within(section).findByText("8:00 a. m. – 12:00 p. m.")).toBeTruthy();
    expect(within(section).queryByRole("button", { name: "Guardar horario" })).toBeNull();
  });
});

describe("Profesionales: ausencias de la sucursal", () => {
  const vacation = timeOff(
    "t1",
    { professionalId: "p1" },
    "2026-11-20T15:00:00.000Z",
    "2026-11-21T15:00:00.000Z",
    "Vacaciones",
  );

  it("lista las ausencias, crea una con la hora local convertida a UTC y borra otra", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain], timeOffs: { p1: [vacation] } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Ausencias" });
    expect(await within(section).findByText("Vacaciones")).toBeTruthy();

    await fillWallClock(user, section, "Desde", "2026-12-01T09:00");
    await fillWallClock(user, section, "Hasta", "2026-12-01T12:00");
    await user.type(within(section).getByLabelText("Motivo (opcional)"), "Capacitación");
    await user.click(within(section).getByRole("button", { name: "Agregar ausencia" }));

    await waitFor(() => expect(backend.createdTimeOffs).toHaveLength(1));
    expect(backend.createdTimeOffs[0]).toEqual({
      owner: "p1",
      branchId: ids.branchA,
      body: {
        starts_at: "2026-12-01T15:00:00.000Z",
        ends_at: "2026-12-01T18:00:00.000Z",
        reason: "Capacitación",
      },
    });
    expect(await within(section).findByText("Capacitación")).toBeTruthy();

    await user.click(within(section).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
    await waitFor(() => expect(backend.deletedTimeOffs).toEqual([{ owner: "p1", id: "t1" }]));
  });

  it("sin time_off.manage se listan pero no hay formulario ni quitar (gate)", async () => {
    asCompanyManager(STAFF_READER_PERMISSIONS);
    servicesBackend();
    staffBackend({ professionals: [efrain], timeOffs: { p1: [vacation] } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Don Efraín");
    const section = await within(panel).findByRole("region", { name: "Ausencias" });
    expect(await within(section).findByText("Vacaciones")).toBeTruthy();
    expect(within(section).queryByLabelText("Desde")).toBeNull();
    expect(within(section).queryByRole("button", { name: /Quitar ausencia/ })).toBeNull();
  });
});

describe("Profesionales: sin sucursales (ausencias pendientes y aviso al asignar)", () => {
  const pending = [
    timeOff(
      "c1",
      { professionalId: "p2" },
      "2026-11-20T15:00:00.000Z",
      "2026-11-21T15:00:00.000Z",
      "Cita médica",
    ),
    timeOff(
      "c2",
      { professionalId: "p2" },
      "2026-12-05T15:00:00.000Z",
      "2026-12-05T20:00:00.000Z",
      null,
    ),
  ];

  it("lista 'Ausencias pendientes' por la ruta de empresa y las borra", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    const section = await within(panel).findByRole("region", { name: "Ausencias pendientes" });
    expect(await within(section).findByText("Cita médica")).toBeTruthy();

    await user.click(within(section).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
    await waitFor(() =>
      expect(backend.deletedCompanyTimeOffs).toEqual([{ owner: "p2", id: "c1" }]),
    );
    await waitFor(() => expect(within(section).queryByText("Cita médica")).toBeNull());
  });

  it("sin sucursal elegida, las ausencias pendientes se muestran en la zona de la primera sucursal de la empresa y la nombran", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [{ ...centro, time_zone: "America/New_York" }],
    });
    servicesBackend();
    staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    const section = await within(panel).findByRole("region", { name: "Ausencias pendientes" });

    expect((await within(section).findAllByText(/10:00/)).length).toBeGreaterThan(0);
    expect(within(section).getByText(/America\/New_York/)).toBeTruthy();
  });

  it("si la ruta de empresa responde 403 la sección no aparece", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffsForbidden: true });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await waitFor(() => expect(backend.companyTimeOffReads).toBeGreaterThan(0));
    await within(panel).findByRole("region", { name: "Sucursales" });
    expect(within(panel).queryByRole("region", { name: "Ausencias pendientes" })).toBeNull();
  });

  it("con una sucursal en el contexto (gerente de sucursal) ni se consulta la ruta de empresa ni aparece la sección", async () => {
    asBranchManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await within(panel).findByRole("region", { name: "Sucursales" });
    expect(within(panel).queryByRole("region", { name: "Ausencias pendientes" })).toBeNull();
    expect(backend.companyTimeOffReads).toBe(0);
  });

  it("un recepcionista con permisos de gestión de personal y sin sucursal en el contexto no consulta la ruta de empresa: no tiene time_off.read de empresa", async () => {
    signedInBackend({
      me: meFixture({
        role: "receptionist",
        permissions: STAFF_MANAGER_PERMISSIONS,
        companyPermissions: [],
        branch: null,
      }),
      branches: [centro],
    });
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await within(panel).findByRole("region", { name: "Sucursales" });
    expect(within(panel).queryByRole("region", { name: "Ausencias pendientes" })).toBeNull();
    expect(backend.companyTimeOffReads).toBe(0);
  });

  it("asignar con ausencias legibles pide confirmar diciendo cuántas hay y que el gerente verá los motivos", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await within(panel).findByRole("region", { name: "Ausencias pendientes" });
    await user.click(within(panel).getByRole("checkbox", { name: "Sucursal Centro" }));

    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText(/2 ausencias registradas/)).toBeTruthy();
    expect(within(dialog).getByText(/verá sus motivos/)).toBeTruthy();
    expect(backend.assignments).toHaveLength(0);

    await user.click(within(dialog).getByRole("button", { name: "Asignar" }));
    await waitFor(() =>
      expect(backend.assignments).toEqual([{ branchId: ids.branchA, professionalId: "p2" }]),
    );
  });

  it("cancelar el diálogo no asigna", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await within(panel).findByRole("region", { name: "Ausencias pendientes" });
    await user.click(within(panel).getByRole("checkbox", { name: "Sucursal Centro" }));
    const dialog = await screen.findByRole("dialog");
    await user.click(within(dialog).getByRole("button", { name: "Cancelar" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(backend.assignments).toHaveLength(0);
  });

  it("con la lista de empresa legible y vacía asigna directo, sin diálogo", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: [] } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await waitFor(() => expect(backend.companyTimeOffReads).toBeGreaterThan(0));
    const box = await within(panel).findByRole("checkbox", { name: "Sucursal Centro" });
    // Assigning waits until the absences are known: only then can it tell "none" from "not loaded yet".
    await waitFor(() => expect(box).toHaveProperty("disabled", false));
    await user.click(box);

    await waitFor(() => expect(backend.assignments).toHaveLength(1));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("sin poder leerlas (403) el aviso es genérico y solo para profesionales sin sucursales", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({
      professionals: [sandra, efrain],
      companyTimeOffsForbidden: true,
    });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await waitFor(() => expect(backend.companyTimeOffReads).toBeGreaterThan(0));
    const box = await within(panel).findByRole("checkbox", { name: "Sucursal Centro" });
    await waitFor(() => expect(box).toHaveProperty("disabled", false));
    await user.click(box);
    const dialog = await screen.findByRole("dialog");
    expect(
      within(dialog).getByText(/Si este profesional tiene ausencias registradas/),
    ).toBeTruthy();
    expect(within(dialog).queryByText(/\d+ ausencias/)).toBeNull();
    await user.click(within(dialog).getByRole("button", { name: "Asignar" }));
    await waitFor(() => expect(backend.assignments).toHaveLength(1));
  });

  it("el gerente de sucursal asigna con el aviso genérico (no puede leer las de empresa)", async () => {
    asBranchManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const panel = await openPanel(user, "Sandra Gómez");
    await user.click(await within(panel).findByRole("checkbox", { name: "Sucursal Centro" }));
    const dialog = await screen.findByRole("dialog");
    expect(
      within(dialog).getByText(/Si este profesional tiene ausencias registradas/),
    ).toBeTruthy();
    expect(backend.companyTimeOffReads).toBe(0);
  });
});
