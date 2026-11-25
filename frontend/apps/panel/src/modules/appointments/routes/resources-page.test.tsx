import { screen, waitFor, within } from "@testing-library/react";
import { delay, http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { CATALOG } from "../../../test/catalog-backend";
import {
  API,
  branch,
  ids,
  meFixture,
  problem,
  resource,
  scheduleSlot,
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

const sillon = resource("r1", "Sillón 1", { kind: "chair" });
const sala = resource("r2", "Sala de color", { kind: "room", active: false });

const asManager = (permissions = STAFF_MANAGER_PERMISSIONS) =>
  signedInBackend({
    me: meFixture({ role: "company_manager", permissions }),
    branches: [centro],
  });

async function openResources() {
  const view = await renderApp({ route: "/resources" });
  await screen.findByRole("heading", { level: 1, name: "Recursos" });
  return view;
}

describe("Recursos", () => {
  it("sin recursos muestra el estado vacío con la acción solo si hay resource.manage", async () => {
    asManager();
    staffBackend();
    const { user } = await openResources();

    expect(await screen.findByRole("heading", { name: "Agregue su primer recurso" })).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar recurso" }));
    expect(await screen.findByRole("dialog", { name: "Nuevo recurso" })).toBeTruthy();
  });

  it("un lector no ve la acción del estado vacío ni 'Nuevo recurso' (gate)", async () => {
    asManager(STAFF_READER_PERMISSIONS);
    staffBackend();
    await openResources();

    expect(await screen.findByRole("heading", { name: "Agregue su primer recurso" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Agregar recurso" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Nuevo recurso" })).toBeNull();
  });

  it("lista solo los recursos de la sucursal de trabajo con nombre, tipo y estado", async () => {
    asManager();
    staffBackend({
      resources: [
        sillon,
        sala,
        resource("r3", "Sillón de otra sucursal", { branch_id: ids.branchA2 }),
      ],
    });
    await openResources();

    const row = (await screen.findByText("Sillón 1")).closest("tr")!;
    expect(within(row).getByText("Sillón")).toBeTruthy();
    expect(within(row).getByText("Activo")).toBeTruthy();
    const paused = screen.getByText("Sala de color").closest("tr")!;
    expect(within(paused).getByText("Pausado")).toBeTruthy();
    expect(screen.queryByText("Sillón de otra sucursal")).toBeNull();
  });

  describe("modal de alta en dos pasos", () => {
    async function fillData(user: Awaited<ReturnType<typeof openResources>>["user"]) {
      await user.click(await screen.findByRole("button", { name: "Nuevo recurso" }));
      const dialog = await screen.findByRole("dialog", { name: "Nuevo recurso" });
      await user.type(within(dialog).getByLabelText("Nombre"), "Camilla 1");
      await user.click(within(dialog).getByRole("combobox", { name: "Tipo" }));
      await user.click(await screen.findByRole("option", { name: "Equipo" }));
      return dialog;
    }

    it("Datos crea el recurso al continuar y Horario lo guarda al terminar", async () => {
      asManager();
      const backend = staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await fillData(user);
      await user.click(within(dialog).getByRole("button", { name: "Continuar" }));

      await waitFor(() => expect(backend.createdResources).toHaveLength(1));
      expect(backend.createdResources[0]).toEqual({
        branchId: ids.branchA,
        body: { name: "Camilla 1", kind: "equipment", active: true },
      });
      const created = await screen.findByRole("dialog", { name: "Camilla 1" });
      const current = within(created).getByRole("list", { name: "Pasos" });
      expect(within(current).getByText("Horario").closest("li")!.getAttribute("aria-current")).toBe(
        "step",
      );

      const tuesday = await within(created).findByRole("group", { name: "Martes" });
      await user.click(within(tuesday).getByRole("button", { name: "Agregar franja" }));
      expect(within(created).queryAllByRole("button", { name: /guardar/i })).toHaveLength(0);
      await user.click(within(created).getByRole("button", { name: "Terminar" }));

      await waitFor(() => expect(backend.schedulePuts).toHaveLength(1));
      expect(backend.schedulePuts[0]!.owner).toMatch(/^r-new/);
      await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
      expect(await screen.findByRole("button", { name: "Ver Camilla 1" })).toBeTruthy();
    });

    it("el horario se puede omitir: cierra sin más peticiones", async () => {
      asManager();
      const backend = staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await fillData(user);
      await user.click(within(dialog).getByRole("button", { name: "Continuar" }));
      const created = await screen.findByRole("dialog", { name: "Camilla 1" });
      await user.click(within(created).getByRole("button", { name: "Omitir por ahora" }));

      await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
      expect(backend.createdResources).toHaveLength(1);
      expect(backend.schedulePuts).toHaveLength(0);
    });

    it("Atrás y Continuar no crean un segundo recurso (adversarial)", async () => {
      asManager();
      const backend = staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await fillData(user);
      await user.click(within(dialog).getByRole("button", { name: "Continuar" }));
      const created = await screen.findByRole("dialog", { name: "Camilla 1" });
      await user.click(within(created).getByRole("button", { name: "Atrás" }));
      await user.click(await within(created).findByRole("button", { name: "Continuar" }));

      expect(await within(created).findByRole("group", { name: "Martes" })).toBeTruthy();
      expect(backend.createdResources).toHaveLength(1);
      expect(backend.patchedResources).toHaveLength(0);
    });
  });

  describe("modal de edición en pestañas", () => {
    async function openEdit(user: Awaited<ReturnType<typeof openResources>>["user"]) {
      await user.click(await screen.findByRole("button", { name: "Ver Sillón 1" }));
      const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
      await user.click(within(panel).getByRole("button", { name: "Editar recurso" }));
      return screen.findByRole("dialog", { name: "Sillón 1" });
    }

    it("cada pestaña tiene un solo botón de guardar en el pie", async () => {
      asManager();
      staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
      expect(
        within(tabs)
          .getAllByRole("tab")
          .map((tab) => tab.textContent),
      ).toEqual(["Datos", "Horario", "Ausencias"]);
      expect(within(dialog).getAllByRole("button", { name: /guardar/i })).toHaveLength(1);

      await user.click(within(tabs).getByRole("tab", { name: "Horario" }));
      await within(dialog).findByRole("group", { name: "Martes" });
      expect(within(dialog).getAllByRole("button", { name: /guardar/i })).toHaveLength(1);

      // Absences are added one at a time: the footer's only action adds the one in the form.
      await user.click(within(tabs).getByRole("tab", { name: "Ausencias" }));
      await within(dialog).findByRole("group", { name: "Desde" });
      expect(within(dialog).queryAllByRole("button", { name: /guardar/i })).toHaveLength(0);
      expect(within(dialog).getAllByRole("button", { name: "Agregar ausencia" })).toHaveLength(1);
    });

    it("mientras carga el horario, Horario muestra la carga y no ofrece guardar", async () => {
      asManager();
      staffBackend({ resources: [sillon] });
      server.use(
        http.get(
          `${CATALOG}/appointments/branches/:branchId/resources/:ownerId/schedule`,
          async () => {
            await delay("infinite");
            return HttpResponse.json({});
          },
        ),
      );
      const { user } = await openResources();

      const dialog = await openEdit(user);
      const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
      await user.click(within(tabs).getByRole("tab", { name: "Horario" }));
      expect(await within(dialog).findByRole("status")).toBeTruthy();
      expect(within(dialog).queryByRole("button", { name: /guardar/i })).toBeNull();
    });

    it("si las ausencias fallan, Ausencias muestra el error con reintentar y no ofrece agregar", async () => {
      asManager();
      staffBackend({ resources: [sillon] });
      server.use(
        http.get(`${CATALOG}/appointments/branches/:branchId/resources/:ownerId/time_offs`, () =>
          HttpResponse.json(problem(500, "internal"), { status: 500 }),
        ),
      );
      const { user } = await openResources();

      const dialog = await openEdit(user);
      const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
      await user.click(within(tabs).getByRole("tab", { name: "Ausencias" }));
      expect(await within(dialog).findByRole("button", { name: "Reintentar" })).toBeTruthy();
      expect(within(dialog).queryByRole("button", { name: /agregar ausencia/i })).toBeNull();
    });

    it("Datos guarda por PATCH y el recurso se archiva desde la tabla", async () => {
      asManager();
      const backend = staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      await user.click(within(dialog).getByRole("switch", { name: "Disponible" }));
      await user.click(within(dialog).getByRole("button", { name: "Guardar cambios" }));
      await waitFor(() => expect(backend.patchedResources).toHaveLength(1));
      expect(backend.patchedResources[0]).toEqual({
        id: "r1",
        body: { name: "Sillón 1", kind: "chair", active: false },
      });

      await user.click(within(dialog).getByRole("button", { name: "Cerrar" }));
      await user.click(screen.getByRole("button", { name: "Archivar Sillón 1" }));
      await waitFor(() => expect(backend.archivedResources).toEqual(["r1"]));
    });

    it("cambiar de pestaña con cambios sin guardar pide confirmar", async () => {
      asManager();
      staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      await user.type(within(dialog).getByLabelText("Nombre"), " grande");
      await user.click(within(dialog).getByRole("tab", { name: "Horario" }));

      expect(
        await screen.findByRole("alertdialog", { name: "¿Descartar los cambios?" }),
      ).toBeTruthy();
    });

    it("Horario guarda con PUT desde el pie", async () => {
      asManager();
      const backend = staffBackend({
        resources: [sillon],
        schedules: { r1: [scheduleSlot("sl1", 2, "09:00", "13:00")] },
      });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      await user.click(within(dialog).getByRole("tab", { name: "Horario" }));
      const tuesday = await within(dialog).findByRole("group", { name: "Martes" });
      await user.click(within(tuesday).getByRole("button", { name: "Agregar franja" }));
      await user.click(within(dialog).getByRole("button", { name: "Guardar horario" }));

      await waitFor(() => expect(backend.schedulePuts).toHaveLength(1));
      expect(backend.schedulePuts[0]!.owner).toBe("r1");
    });

    it("Ausencias: agrega desde el pie con la hora local convertida a UTC y quita otra de la lista", async () => {
      asManager();
      const maintenance = timeOff(
        "t1",
        { resourceId: "r1" },
        "2026-11-20T15:00:00.000Z",
        "2026-11-20T18:00:00.000Z",
        "Mantenimiento",
      );
      const backend = staffBackend({ resources: [sillon], timeOffs: { r1: [maintenance] } });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      await user.click(within(dialog).getByRole("tab", { name: "Ausencias" }));
      expect(await within(dialog).findByText("Mantenimiento")).toBeTruthy();

      await fillWallClock(user, dialog, "Desde", "2026-12-02T08:00");
      await fillWallClock(user, dialog, "Hasta", "2026-12-02T09:00");
      await user.click(within(dialog).getByRole("button", { name: "Agregar ausencia" }));
      await waitFor(() => expect(backend.createdTimeOffs).toHaveLength(1));
      expect(backend.createdTimeOffs[0]!.body).toEqual({
        starts_at: "2026-12-02T14:00:00.000Z",
        ends_at: "2026-12-02T15:00:00.000Z",
        reason: null,
      });

      await user.click(within(dialog).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
      await waitFor(() => expect(backend.deletedTimeOffs).toEqual([{ owner: "r1", id: "t1" }]));
    });

    it("el gerente de sucursal sin resource.manage solo ve las pestañas que puede escribir", async () => {
      asManager(
        STAFF_MANAGER_PERMISSIONS.filter((item) => item !== "appointments.resource.manage"),
      );
      staffBackend({ resources: [sillon] });
      const { user } = await openResources();

      const dialog = await openEdit(user);
      const tabs = within(dialog).getByRole("tablist", { name: "Secciones" });
      expect(
        within(tabs)
          .getAllByRole("tab")
          .map((tab) => tab.textContent),
      ).toEqual(["Horario", "Ausencias"]);
    });
  });

  it("con «Todas las sucursales» y varias sucursales pide elegir una en el selector global, sin tabla (adversarial)", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [centro, norte],
    });
    staffBackend({ resources: [sillon] });
    await openResources();

    expect(await screen.findByRole("heading", { name: "Elija una sucursal" })).toBeTruthy();
    expect(screen.queryByRole("table")).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
    expect(screen.queryByRole("button", { name: "Nuevo recurso" })).toBeNull();
  });

  it("si las sucursales no cargan, muestra el encabezado y el error con reintentar, no una página en blanco", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [centro, norte],
    });
    staffBackend({ resources: [sillon] });
    server.use(
      http.get(`${API}/api/v1/organizations/:org/companies/:company/branches`, () =>
        HttpResponse.json(problem(500, "internal"), { status: 500 }),
      ),
    );
    await openResources();

    expect(await screen.findByRole("button", { name: "Reintentar" })).toBeTruthy();
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("una empresa sin sucursales ve el encabezado y un estado vacío que lo explica", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [],
    });
    staffBackend({ resources: [sillon] });
    await openResources();

    expect(await screen.findByRole("heading", { name: "Todavía no hay sucursales" })).toBeTruthy();
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("recepción (AC8): sin crear ni acciones; la fila abre el detalle flotante de lectura, sin modal ni formularios", async () => {
    asManager(STAFF_READER_PERMISSIONS);
    staffBackend({
      resources: [sillon],
      schedules: { r1: [scheduleSlot("sl1", 2, "09:00", "13:00")] },
    });
    const { user } = await openResources();

    expect(await screen.findByText("Solo lectura")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Nuevo recurso" })).toBeNull();
    expect(screen.queryByRole("columnheader", { name: "Acciones" })).toBeNull();
    expect(screen.queryByRole("button", { name: /Archivar/ })).toBeNull();

    await user.click(await screen.findByRole("button", { name: "Ver Sillón 1" }));
    const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
    expect(panel.closest("[data-variant=floating]")).not.toBeNull();
    expect(within(panel).getByText("Sillón")).toBeTruthy();
    const schedule = await within(panel).findByRole("region", { name: "Horario semanal" });
    expect(await within(schedule).findByText("9:00 a. m. – 1:00 p. m.")).toBeTruthy();
    const absences = await within(panel).findByRole("region", { name: "Ausencias" });
    expect(within(absences).queryByRole("group", { name: "Desde" })).toBeNull();
    expect(within(panel).queryByRole("button", { name: /Editar|Guardar|Agregar/ })).toBeNull();
    expect(within(panel).queryByText(/Todo se guarda en la hora/)).toBeNull();
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it.each([
    {
      case: "sin schedule.read ni time_off.read",
      permissions: ["appointments.resource.read", "appointments.resource.manage"],
      requested: [],
    },
    {
      case: "solo con schedule.read",
      permissions: ["appointments.resource.read", "appointments.schedule.read"],
      requested: ["/schedule"],
    },
    {
      case: "solo con time_off.read",
      permissions: ["appointments.resource.read", "appointments.time_off.read"],
      requested: ["/time_offs"],
    },
  ])(
    "$case, el panel pide solo lo que puede leer (sin 403 de ruido)",
    async ({ permissions, requested }) => {
      asManager(permissions);
      staffBackend({ resources: [sillon] });
      const urls: string[] = [];
      server.events.on("request:start", ({ request }) => {
        urls.push(new URL(request.url).pathname);
      });
      const { user } = await openResources();

      await user.click(await screen.findByRole("button", { name: "Ver Sillón 1" }));
      await screen.findByRole("complementary", { name: "Sillón 1" });
      await new Promise((resolve) => setTimeout(resolve, 100));
      server.events.removeAllListeners();

      const ownerRequests = urls.filter((url) => /\/resources\/r1\//.test(url));
      expect(ownerRequests.map((url) => url.slice(url.lastIndexOf("/")))).toEqual(requested);
    },
  );
});
