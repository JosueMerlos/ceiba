import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { delay, http, HttpResponse } from "msw";
import { CATALOG, servicesBackend } from "../../../test/catalog-backend";
import {
  branch,
  ids,
  meFixture,
  problem,
  professional,
  scheduleSlot,
  service,
  timeOff,
} from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { fillWallClock } from "../../../test/date-time-fields";
import { server, signedInBackend } from "../../../test/server";
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

// A branch manager writes hours, absences and assignments, never the profile, services or contact.
const BRANCH_MANAGER = STAFF_MANAGER_PERMISSIONS.filter(
  (item) => item !== "appointments.professional.manage",
);

/** The company manager works at company level (no branch in the context). */
const asCompanyManager = (permissions = STAFF_MANAGER_PERMISSIONS, branches = [centro]) =>
  signedInBackend({
    me: meFixture({ role: "company_manager", permissions, branch: null }),
    branches,
  });

/** A branch manager has the branch in the context: company-scope routes are not theirs. */
const asBranchManager = (permissions = BRANCH_MANAGER) =>
  signedInBackend({
    me: meFixture({ role: "receptionist", permissions, branch: centro }),
    branches: [centro],
  });

type User = Awaited<ReturnType<typeof openProfessionals>>["user"];

async function openProfessionals() {
  const view = await renderApp({ route: "/professionals" });
  await screen.findByRole("heading", { level: 1, name: "Profesionales" });
  return view;
}

/** Row -> floating detail -> "Editar profesional": the edit modal. */
async function openEdit(user: User, name: string) {
  await user.click(await screen.findByRole("button", { name: `Ver ${name}` }));
  const panel = await screen.findByRole("complementary", { name });
  await user.click(within(panel).getByRole("button", { name: "Editar profesional" }));
  return screen.findByRole("dialog", { name });
}

async function openTab(user: User, dialog: HTMLElement, name: string) {
  const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
  await user.click(within(tabs).getByRole("tab", { name }));
}

const footerOf = (dialog: HTMLElement) =>
  dialog.querySelector<HTMLElement>('[data-slot="form-dialog-footer"]')!;

const currentStep = (dialog: HTMLElement) =>
  within(within(dialog).getByRole("list", { name: "Pasos" }))
    .getAllByRole("listitem")
    .find((item) => item.getAttribute("aria-current") === "step")?.textContent;

describe("Profesionales: lista y gates", () => {
  it("sin profesionales muestra 'Agregue su primer profesional' y la acción abre el modal de alta", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend();
    const { user } = await openProfessionals();

    expect(
      await screen.findByRole("heading", { name: "Agregue su primer profesional" }),
    ).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar profesional" }));
    expect(await screen.findByRole("dialog", { name: "Nuevo profesional" })).toBeTruthy();
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

  it("archiva desde la tabla con DELETE y desaparece de la lista", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    await user.click(await screen.findByRole("button", { name: "Archivar Don Efraín" }));
    await waitFor(() => expect(backend.archivedProfessionals).toEqual(["p1"]));
    await waitFor(() => expect(screen.queryByText("Don Efraín")).toBeNull());
  });

  it("recepción (AC8): sin crear ni acciones; la fila abre el detalle flotante de lectura, sin editar ni modal", async () => {
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
    expect(within(panel).queryByRole("button", { name: /Guardar|Agregar|Editar/ })).toBeNull();
    expect(document.querySelectorAll("[data-slot=form-description]")).toHaveLength(0);
    expect(within(panel).queryByText(/Todo se guarda en la hora/)).toBeNull();
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("Profesionales: alta por pasos", () => {
  async function fillProfile(user: User) {
    await user.click(await screen.findByRole("button", { name: "Nuevo profesional" }));
    const dialog = await screen.findByRole("dialog", { name: "Nuevo profesional" });
    await user.type(within(dialog).getByLabelText("Nombre para mostrar"), "Marlon Ruiz");
    await user.type(within(dialog).getByLabelText("Teléfono (opcional)"), "8888 1234");
    await user.type(within(dialog).getByLabelText("Correo (opcional)"), "marlon@ej.com");
    return dialog;
  }

  it("Perfil crea con teléfono y correo; los demás pasos se omiten hasta Terminar sin más peticiones (AC1)", async () => {
    asCompanyManager();
    servicesBackend({ services: [corte] });
    const backend = staffBackend();
    const { user } = await openProfessionals();

    const dialog = await fillProfile(user);
    expect(
      within(footerOf(dialog)).getByText("Paso 1 de 4. Al continuar, el profesional queda creado."),
    ).toBeTruthy();
    await user.click(within(dialog).getByRole("button", { name: "Crear y continuar" }));

    await waitFor(() => expect(backend.createdProfessionals).toHaveLength(1));
    expect(backend.createdProfessionals[0]).toEqual({
      display_name: "Marlon Ruiz",
      active: true,
      phone: "8888 1234",
      email: "marlon@ej.com",
    });
    const created = await screen.findByRole("dialog", { name: "Marlon Ruiz" });
    expect(currentStep(created)).toContain("Servicios");
    expect(
      within(footerOf(created)).getByText("Paso 2 de 4. Puede completarlo después."),
    ).toBeTruthy();

    await user.click(within(created).getByRole("button", { name: "Omitir por ahora" }));
    expect(currentStep(created)).toContain("Sucursal y horario");
    await user.click(within(created).getByRole("button", { name: "Omitir por ahora" }));
    expect(currentStep(created)).toContain("Ausencias");
    await user.click(within(created).getByRole("button", { name: "Terminar" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(backend.createdProfessionals).toHaveLength(1);
    expect(backend.patchedProfessionals).toHaveLength(0);
    expect(backend.servicePuts).toHaveLength(0);
    expect(backend.assignments).toHaveLength(0);
    expect(backend.schedulePuts).toHaveLength(0);
    expect(backend.createdTimeOffs).toHaveLength(0);
    expect(await screen.findByRole("button", { name: "Ver Marlon Ruiz" })).toBeTruthy();
  });

  it("un 422 en el teléfono deja el paso 1 abierto con el error junto al campo (adversarial)", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({ invalidPhone: true });
    const { user } = await openProfessionals();

    const dialog = await fillProfile(user);
    await user.click(within(dialog).getByRole("button", { name: "Crear y continuar" }));

    const phone = within(dialog).getByLabelText("Teléfono (opcional)");
    await waitFor(() => expect(phone.getAttribute("aria-invalid")).toBe("true"));
    expect(
      within(phone.closest("[data-slot=form-item]")!).getByText("no es un teléfono válido"),
    ).toBeTruthy();
    expect(screen.getByRole("dialog", { name: "Nuevo profesional" })).toBe(dialog);
    expect(currentStep(dialog)).toContain("Perfil");
  });

  it("Atrás y Continuar no crean un segundo profesional; un cambio se guarda con PATCH (adversarial)", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend();
    const { user } = await openProfessionals();

    const dialog = await fillProfile(user);
    await user.click(within(dialog).getByRole("button", { name: "Crear y continuar" }));
    const created = await screen.findByRole("dialog", { name: "Marlon Ruiz" });

    await user.click(within(created).getByRole("button", { name: "Atrás" }));
    await user.click(await within(created).findByRole("button", { name: "Guardar y continuar" }));
    await waitFor(() => expect(currentStep(created)).toContain("Servicios"));
    expect(backend.createdProfessionals).toHaveLength(1);
    expect(backend.patchedProfessionals).toHaveLength(0);

    await user.click(within(created).getByRole("button", { name: "Atrás" }));
    const name = await within(created).findByLabelText("Nombre para mostrar");
    await user.type(name, " B.");
    await user.click(within(created).getByRole("button", { name: "Guardar y continuar" }));

    await waitFor(() => expect(backend.patchedProfessionals).toHaveLength(1));
    expect(backend.createdProfessionals).toHaveLength(1);
    expect(backend.patchedProfessionals[0]).toEqual({
      id: "p-new-1",
      body: {
        display_name: "Marlon Ruiz B.",
        active: true,
        phone: "8888 1234",
        email: "marlon@ej.com",
      },
    });
  });

  it("en el paso 4, Terminar agrega la ausencia del formulario y cierra", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend();
    const { user } = await openProfessionals();

    const dialog = await fillProfile(user);
    await user.click(within(dialog).getByRole("button", { name: "Crear y continuar" }));
    const created = await screen.findByRole("dialog", { name: "Marlon Ruiz" });
    await user.click(within(created).getByRole("button", { name: "Omitir por ahora" }));

    await user.click(await within(created).findByRole("checkbox", { name: "Sucursal Centro" }));
    await waitFor(() => expect(backend.assignments).toHaveLength(1));
    await within(created).findByRole("group", { name: "Lunes" });
    await user.click(within(created).getByRole("button", { name: "Guardar y continuar" }));
    await waitFor(() => expect(currentStep(created)).toContain("Ausencias"));
    expect(backend.schedulePuts).toHaveLength(0);

    await within(created).findByRole("group", { name: "Desde" });
    await fillWallClock(user, created, "Desde", "2026-12-01T09:00");
    await fillWallClock(user, created, "Hasta", "2026-12-01T12:00");
    await user.click(within(created).getByRole("button", { name: "Terminar" }));

    await waitFor(() => expect(backend.createdTimeOffs).toHaveLength(1));
    expect(backend.createdTimeOffs[0]).toEqual({
      owner: "p-new-1",
      branchId: ids.branchA,
      body: {
        starts_at: "2026-12-01T15:00:00.000Z",
        ends_at: "2026-12-01T18:00:00.000Z",
        reason: null,
      },
    });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});

describe("Profesionales: edición en pestañas", () => {
  it("el gerente de empresa ve las cuatro pestañas y en cada una hay un solo botón en el pie (AC4)", async () => {
    asCompanyManager();
    servicesBackend({ services: [corte] });
    staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
    expect(
      within(tabs)
        .getAllByRole("tab")
        .map((tab) => tab.textContent),
    ).toEqual(["Perfil", "Servicios", "Sucursal y horario", "Ausencias"]);

    const actions = /guardar|agregar ausencia/i;
    const expectOneAction = (name: string) => {
      expect(within(footerOf(dialog)).getAllByRole("button", { name: actions })).toHaveLength(1);
      expect(within(dialog).getAllByRole("button", { name: actions })).toHaveLength(1);
      expect(within(footerOf(dialog)).getByText(`Se guarda solo la pestaña ${name}.`)).toBeTruthy();
    };

    await within(dialog).findByLabelText("Nombre para mostrar");
    expectOneAction("Perfil");

    await openTab(user, dialog, "Servicios");
    await within(dialog).findByRole("checkbox", { name: "Corte clásico" });
    expectOneAction("Servicios");

    await openTab(user, dialog, "Sucursal y horario");
    await within(dialog).findByRole("group", { name: "Lunes" });
    expectOneAction("Sucursal y horario");

    await openTab(user, dialog, "Ausencias");
    await within(dialog).findByRole("group", { name: "Desde" });
    expect(within(footerOf(dialog)).getByRole("button", { name: "Agregar ausencia" })).toBeTruthy();
    expectOneAction("Ausencias");
  });

  it("Perfil precarga el contacto de la ficha y guarda con PATCH", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({
      professionals: [efrain],
      contacts: { p1: { phone: "+50588881234", email: null } },
    });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    const phone = within(dialog).getByLabelText("Teléfono (opcional)");
    await waitFor(() => expect(phone).toHaveProperty("value", "+50588881234"));
    await user.type(within(dialog).getByLabelText("Correo (opcional)"), "efrain@ej.com");
    await user.click(within(dialog).getByRole("switch", { name: "Atiende citas" }));
    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(backend.patchedProfessionals).toHaveLength(1));
    expect(backend.patchedProfessionals[0]).toEqual({
      id: "p1",
      body: {
        display_name: "Don Efraín",
        active: false,
        phone: "+50588881234",
        email: "efrain@ej.com",
      },
    });
  });

  it("mientras carga la ficha, Perfil muestra la carga y no ofrece guardar", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    server.use(
      http.get(`${CATALOG}/appointments/professionals/:id`, async () => {
        await delay("infinite");
        return HttpResponse.json({});
      }),
    );
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    expect(await within(dialog).findByRole("status")).toBeTruthy();
    expect(within(dialog).queryByLabelText("Nombre para mostrar")).toBeNull();
    expect(within(dialog).queryByRole("button", { name: /guardar/i })).toBeNull();
  });

  it("si la ficha falla, Perfil muestra el error con reintentar y no ofrece guardar", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    server.use(
      http.get(`${CATALOG}/appointments/professionals/:id`, () =>
        HttpResponse.json(problem(500, "internal"), { status: 500 }),
      ),
    );
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    expect(await within(dialog).findByRole("button", { name: "Reintentar" })).toBeTruthy();
    expect(within(dialog).getByRole("alert")).toBeTruthy();
    expect(within(dialog).queryByRole("button", { name: /guardar/i })).toBeNull();
  });

  it("si los servicios fallan, la pestaña Servicios muestra el error con reintentar y no ofrece guardar", async () => {
    asCompanyManager();
    staffBackend({ professionals: [efrain] });
    server.use(
      http.get(`${CATALOG}/appointments/services`, () =>
        HttpResponse.json(problem(500, "internal"), { status: 500 }),
      ),
    );
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await within(dialog).findByLabelText("Nombre para mostrar");
    await openTab(user, dialog, "Servicios");
    expect(await within(dialog).findByRole("button", { name: "Reintentar" })).toBeTruthy();
    expect(within(dialog).queryByRole("button", { name: /guardar/i })).toBeNull();
  });

  it("el gerente de sucursal solo ve Sucursal y horario y Ausencias, sin contacto ni lectura de la ficha", async () => {
    asBranchManager();
    servicesBackend({ services: [corte] });
    const backend = staffBackend({
      professionals: [efrain],
      contacts: { p1: { phone: "+50588881234", email: "efrain@ej.com" } },
    });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
    expect(
      within(tabs)
        .getAllByRole("tab")
        .map((tab) => tab.textContent),
    ).toEqual(["Sucursal y horario", "Ausencias"]);
    await within(dialog).findByRole("group", { name: "Lunes" });
    expect(within(dialog).queryByLabelText("Teléfono (opcional)")).toBeNull();
    expect(within(dialog).queryByLabelText("Correo (opcional)")).toBeNull();

    await openTab(user, dialog, "Ausencias");
    await within(dialog).findByRole("group", { name: "Desde" });
    expect(within(dialog).queryByLabelText("Teléfono (opcional)")).toBeNull();
    expect(backend.professionalReads).toHaveLength(0);
    expect(screen.queryByText("+50588881234")).toBeNull();
  });

  it("una pestaña sin nada que guardar no muestra un botón de guardar en el pie", async () => {
    // Assigns branches but cannot edit hours: the branch tab only has the checkboxes, which apply at once.
    asBranchManager(BRANCH_MANAGER.filter((item) => item !== "appointments.schedule.manage"));
    servicesBackend();
    staffBackend({ professionals: [efrain, sandra] });
    const { user } = await openProfessionals();

    let dialog = await openEdit(user, "Don Efraín");
    await within(dialog).findByRole("checkbox", { name: "Sucursal Centro" });
    expect(within(dialog).queryByRole("button", { name: /guardar/i })).toBeNull();
    await user.click(within(dialog).getByRole("button", { name: "Cerrar" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    // With no branch there is nowhere to add an absence.
    dialog = await openEdit(user, "Sandra Gómez");
    await openTab(user, dialog, "Ausencias");
    await within(dialog).findByText(/Asígnelo a una sucursal/);
    expect(within(dialog).queryByRole("button", { name: /guardar|agregar ausencia/i })).toBeNull();
  });

  it("recepción no tiene botón de editar en el detalle (sin pestañas que escribir)", async () => {
    signedInBackend({
      me: meFixture({
        role: "receptionist",
        permissions: STAFF_READER_PERMISSIONS,
        branch: centro,
      }),
      branches: [centro],
    });
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    await user.click(await screen.findByRole("button", { name: "Ver Don Efraín" }));
    const panel = await screen.findByRole("complementary", { name: "Don Efraín" });
    expect(within(panel).queryByRole("button", { name: "Editar profesional" })).toBeNull();
  });
});

describe("Profesionales: servicios agrupados por categoría (AC5)", () => {
  const CATEGORIES = ["Barbería", "Cabello", "Color", "Spa", "Uñas"];
  const sixty = CATEGORIES.flatMap((category, group) =>
    Array.from({ length: 12 }, (_, index) =>
      service(`c${group + 1}-${index + 1}`, `${category} ${String(index + 1).padStart(2, "0")}`, {
        category,
      }),
    ),
  );
  // Paused: not offered, and it must not count in its group.
  const paused = service("paused-1", "Barbería pausado", { category: "Barbería", active: false });

  async function openServices(user: User) {
    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Servicios");
    await within(dialog).findByRole("group", { name: "Uñas" });
    return dialog;
  }

  it("60 servicios en dos páginas de cursor: 5 grupos con «x de N», seleccionar todos, solo seleccionados y PUT", async () => {
    asCompanyManager();
    const services = servicesBackend({ services: [...sixty, paused], pageSize: 50 });
    const backend = staffBackend({
      professionals: [{ ...efrain, service_ids: ["c1-1"] }],
    });
    const { user } = await openProfessionals();

    const dialog = await openServices(user);
    expect(services.listQueries.some((query) => query.includes("after=50"))).toBe(true);
    const groups = within(dialog).getAllByRole("group");
    expect(groups.map((group) => group.getAttribute("aria-label"))).toEqual(CATEGORIES);
    expect(within(groups[0]!).getByText("1 de 12")).toBeTruthy();
    for (const group of groups.slice(1)) expect(within(group).getByText("0 de 12")).toBeTruthy();
    expect(within(dialog).queryByRole("checkbox", { name: "Barbería pausado" })).toBeNull();
    expect(within(dialog).getAllByRole("checkbox")).toHaveLength(60);
    expect(
      within(dialog).queryByRole("button", { name: /siguiente|anterior|cargar más/i }),
    ).toBeNull();

    const cabello = within(dialog).getByRole("group", { name: "Cabello" });
    await user.click(within(cabello).getByRole("button", { name: "Seleccionar todos" }));
    expect(within(cabello).getByText("12 de 12")).toBeTruthy();
    expect(within(cabello).getByRole("button", { name: "Quitar todos" })).toBeTruthy();

    const onlySelected = within(dialog).getByRole("button", { name: "Solo seleccionados · 13" });
    await user.click(onlySelected);
    expect(onlySelected.getAttribute("aria-pressed")).toBe("true");
    expect(within(dialog).getAllByRole("checkbox")).toHaveLength(13);
    expect(
      within(dialog)
        .getAllByRole("group")
        .map((group) => group.getAttribute("aria-label")),
    ).toEqual(["Barbería", "Cabello"]);

    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" }));
    await waitFor(() => expect(backend.servicePuts).toHaveLength(1));
    const sent = (backend.servicePuts[0]!.body as { service_ids: string[] }).service_ids;
    expect([...sent].sort()).toEqual(
      ["c1-1", ...Array.from({ length: 12 }, (_, index) => `c2-${index + 1}`)].sort(),
    );
  });

  it("un servicio sin categoría va a «Sin categoría», al final; uno que presta y está pausado no se pierde (adversarial)", async () => {
    asCompanyManager();
    servicesBackend({
      services: [
        service("u1", "Manicure", { category: "Uñas" }),
        service("n1", "Corte libre"),
        service("b1", "Afeitado", { category: "Barbería" }),
        paused,
      ],
    });
    const backend = staffBackend({
      professionals: [{ ...efrain, service_ids: ["paused-1"] }],
    });
    const { user } = await openProfessionals();

    const dialog = await openServices(user);
    expect(
      within(dialog)
        .getAllByRole("group")
        .map((group) => group.getAttribute("aria-label")),
    ).toEqual(["Barbería", "Uñas", "Sin categoría"]);
    const none = within(dialog).getByRole("group", { name: "Sin categoría" });
    expect(within(none).getByRole("checkbox", { name: "Corte libre" })).toBeTruthy();

    await user.click(within(none).getByRole("checkbox", { name: "Corte libre" }));
    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" }));
    await waitFor(() => expect(backend.servicePuts).toHaveLength(1));
    expect(backend.servicePuts[0]!.body).toEqual({ service_ids: ["paused-1", "n1"] });
  });

  it("«Contraer todo» pliega los grupos y la búsqueda filtra por nombre", async () => {
    asCompanyManager();
    servicesBackend({ services: sixty.slice(0, 24) });
    staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Servicios");
    await within(dialog).findByRole("group", { name: "Cabello" });

    await user.click(within(dialog).getByRole("button", { name: "Contraer todo" }));
    expect(within(dialog).queryAllByRole("checkbox")).toHaveLength(0);
    await user.click(within(dialog).getByRole("button", { name: "Expandir todo" }));
    expect(within(dialog).getAllByRole("checkbox")).toHaveLength(24);

    await user.type(
      within(dialog).getByRole("searchbox", { name: "Buscar servicio" }),
      "cabello 0",
    );
    expect(within(dialog).getAllByRole("checkbox")).toHaveLength(9);
    expect(within(dialog).queryByRole("group", { name: "Barbería" })).toBeNull();
  });
});

describe("Profesionales: sucursal y horario", () => {
  const bothBranches = { ...efrain, branch_ids: [ids.branchA, ids.branchA2] };

  it("una sub-pestaña por sucursal asignada; abre en la del contexto y cambiar con cambios pide confirmar", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: norte,
      }),
      branches: [centro, norte],
    });
    servicesBackend();
    const backend = staffBackend({
      professionals: [bothBranches],
      schedules: { p1: [scheduleSlot("sl1", 1, "08:00", "12:00")] },
    });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Sucursal y horario");
    const picker = await within(dialog).findByRole("group", { name: "Horario semanal" });
    const chips = within(picker).getAllByRole("button");
    expect(chips.map((chip) => [chip.textContent, chip.getAttribute("aria-pressed")])).toEqual([
      ["Sucursal Centro", "false"],
      ["Sucursal Norte", "true"],
    ]);

    const monday = await within(dialog).findByRole("group", { name: "Lunes" });
    await user.click(within(monday).getByRole("button", { name: "Agregar franja" }));
    await user.click(within(picker).getByRole("button", { name: "Sucursal Centro" }));
    const confirm = await screen.findByRole("alertdialog", { name: "¿Descartar los cambios?" });
    await user.click(within(confirm).getByRole("button", { name: "Seguir editando" }));
    expect(
      within(picker).getByRole("button", { name: "Sucursal Norte" }).getAttribute("aria-pressed"),
    ).toBe("true");

    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" }));
    await waitFor(() => expect(backend.schedulePuts).toHaveLength(1));
    expect(backend.schedulePuts[0]).toEqual({
      owner: "p1",
      branchId: ids.branchA2,
      body: {
        slots: [
          { weekday: 1, starts_at_local: "08:00", ends_at_local: "12:00" },
          { weekday: 1, starts_at_local: "12:00", ends_at_local: "16:00" },
        ],
      },
    });
  });

  it("mientras se guarda el horario, el botón del pie queda ocupado", async () => {
    asCompanyManager();
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    let release = () => {};
    server.use(
      http.put(
        `${CATALOG}/appointments/branches/:branchId/professionals/:ownerId/schedule`,
        () =>
          new Promise<Response>((resolve) => {
            release = () => resolve(HttpResponse.json({ data: [] }));
          }),
      ),
    );
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Sucursal y horario");
    const monday = await within(dialog).findByRole("group", { name: "Lunes" });
    await user.click(within(monday).getByRole("button", { name: "Agregar franja" }));
    const save = within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" });
    await user.click(save);

    await waitFor(() => expect(save.getAttribute("aria-busy")).toBe("true"));
    release();
    await waitFor(() => expect(save.getAttribute("aria-busy")).toBeNull());
  });

  it("las casillas de sucursal asignan y quitan al instante, sin diálogo", async () => {
    asCompanyManager(STAFF_MANAGER_PERMISSIONS, [centro, norte]);
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Sucursal y horario");
    await user.click(await within(dialog).findByRole("checkbox", { name: "Sucursal Norte" }));
    await waitFor(() =>
      expect(backend.assignments).toEqual([{ branchId: ids.branchA2, professionalId: "p1" }]),
    );
    await user.click(within(dialog).getByRole("checkbox", { name: "Sucursal Centro" }));
    await waitFor(() =>
      expect(backend.unassignments).toEqual([{ branchId: ids.branchA, professionalId: "p1" }]),
    );
    expect(screen.queryByRole("dialog", { name: /Asignar a/ })).toBeNull();
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

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Sucursal y horario");
    const monday = await within(dialog).findByRole("group", { name: "Lunes" });
    await user.click(within(monday).getByRole("button", { name: "Agregar franja" }));
    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Guardar cambios" }));

    expect(
      await within(dialog).findByText(/Se cruza con el horario en otra sucursal/),
    ).toBeTruthy();
  });

  it("sin professional.assign las casillas quedan deshabilitadas (gate)", async () => {
    asCompanyManager(
      STAFF_MANAGER_PERMISSIONS.filter((item) => item !== "appointments.professional.assign"),
    );
    servicesBackend();
    staffBackend({ professionals: [efrain] });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Sucursal y horario");
    expect(await within(dialog).findByRole("checkbox", { name: "Sucursal Centro" })).toHaveProperty(
      "disabled",
      true,
    );
  });
});

describe("Profesionales: ausencias", () => {
  const vacation = timeOff(
    "t1",
    { professionalId: "p1" },
    "2026-11-20T15:00:00.000Z",
    "2026-11-21T15:00:00.000Z",
    "Vacaciones",
  );

  it("el pie «Agregar ausencia» la crea en la hora de la sucursal; borrar es inmediato; sin inputs nativos (AC10)", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [efrain], timeOffs: { p1: [vacation] } });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Don Efraín");
    await openTab(user, dialog, "Ausencias");
    expect(await within(dialog).findByText("Vacaciones")).toBeTruthy();
    expect(
      dialog.querySelectorAll(
        'input[type="date"], input[type="time"], input[type="datetime-local"]',
      ),
    ).toHaveLength(0);

    await fillWallClock(user, dialog, "Desde", "2026-12-01T09:00");
    await fillWallClock(user, dialog, "Hasta", "2026-12-01T12:00");
    await user.type(within(dialog).getByLabelText("Motivo (opcional)"), "Capacitación");
    await user.click(within(footerOf(dialog)).getByRole("button", { name: "Agregar ausencia" }));

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
    expect(await within(dialog).findByText("Capacitación")).toBeTruthy();

    await user.click(within(dialog).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
    await waitFor(() => expect(backend.deletedTimeOffs).toEqual([{ owner: "p1", id: "t1" }]));
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

  it("la pestaña Ausencias lista las pendientes por la ruta de empresa y las borra", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Sandra Gómez");
    await openTab(user, dialog, "Ausencias");
    const section = await within(dialog).findByRole("region", { name: "Ausencias pendientes" });
    expect(await within(section).findByText("Cita médica")).toBeTruthy();
    expect(within(section).getByText(/America\/Managua/)).toBeTruthy();

    await user.click(within(section).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
    await waitFor(() =>
      expect(backend.deletedCompanyTimeOffs).toEqual([{ owner: "p2", id: "c1" }]),
    );
  });

  it("asignar con ausencias legibles pide confirmar diciendo cuántas hay; cancelar no asigna", async () => {
    asCompanyManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Sandra Gómez");
    await openTab(user, dialog, "Sucursal y horario");
    const box = await within(dialog).findByRole("checkbox", { name: "Sucursal Centro" });
    await waitFor(() => expect(box).toHaveProperty("disabled", false));

    await user.click(box);
    let confirm = await screen.findByRole("dialog", { name: "Asignar a Sucursal Centro" });
    expect(within(confirm).getByText(/2 ausencias registradas/)).toBeTruthy();
    await user.click(within(confirm).getByRole("button", { name: "Cancelar" }));
    await waitFor(() =>
      expect(screen.queryByRole("dialog", { name: "Asignar a Sucursal Centro" })).toBeNull(),
    );
    expect(backend.assignments).toHaveLength(0);

    await user.click(box);
    confirm = await screen.findByRole("dialog", { name: "Asignar a Sucursal Centro" });
    await user.click(within(confirm).getByRole("button", { name: "Asignar" }));
    await waitFor(() =>
      expect(backend.assignments).toEqual([{ branchId: ids.branchA, professionalId: "p2" }]),
    );
  });

  it("el gerente de sucursal asigna con el aviso genérico y no consulta la ruta de empresa", async () => {
    asBranchManager();
    servicesBackend();
    const backend = staffBackend({ professionals: [sandra], companyTimeOffs: { p2: pending } });
    const { user } = await openProfessionals();

    const dialog = await openEdit(user, "Sandra Gómez");
    await user.click(await within(dialog).findByRole("checkbox", { name: "Sucursal Centro" }));
    const confirm = await screen.findByRole("dialog", { name: "Asignar a Sucursal Centro" });
    expect(
      within(confirm).getByText(/Si este profesional tiene ausencias registradas/),
    ).toBeTruthy();
    expect(backend.companyTimeOffReads).toBe(0);
  });
});
