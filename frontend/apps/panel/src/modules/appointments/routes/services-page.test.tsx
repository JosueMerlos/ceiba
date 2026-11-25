import { screen, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import {
  BRANCH_MANAGER_PERMISSIONS,
  CATALOG,
  MANAGER_PERMISSIONS,
  READER_PERMISSIONS,
  servicesBackend,
} from "../../../test/catalog-backend";
import { branch, ids, meFixture, service, serviceOverride } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { server, signedInBackend } from "../../../test/server";

const corte = service("s1", "Corte clásico", { duration_minutes: 30, price_minor: 20000 });
const tinte = service("s2", "Tinte", { active: false });
const viejo = service("s3", "Peinado antiguo", { archived_at: "2026-11-01T10:00:00.000Z" });

const asManager = () =>
  signedInBackend({ me: meFixture({ role: "company_manager", permissions: MANAGER_PERMISSIONS }) });

async function openServices() {
  const view = await renderApp({ route: "/services" });
  await screen.findByRole("heading", { level: 1, name: "Servicios" });
  return view;
}

describe("Servicios", () => {
  it("sin servicios muestra 'Agregue su primer servicio' y la acción abre el modal de alta", async () => {
    asManager();
    servicesBackend();
    const { user } = await openServices();

    expect(await screen.findByRole("heading", { name: "Agregue su primer servicio" })).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar servicio" }));

    expect(await screen.findByRole("dialog", { name: "Nuevo servicio" })).toBeTruthy();
  });

  it("sin service.manage el estado vacío no ofrece la acción ni 'Nuevo servicio' (gate)", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist", permissions: READER_PERMISSIONS }) });
    servicesBackend();
    await openServices();

    expect(await screen.findByRole("heading", { name: "Agregue su primer servicio" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Agregar servicio" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Nuevo servicio" })).toBeNull();
  });

  it("AC4: un archivado no aparece en Activos; en Archivados se restaura con POST restore", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte, viejo] });
    const { user } = await openServices();

    expect(await screen.findByText("Corte clásico")).toBeTruthy();
    expect(screen.queryByText("Peinado antiguo")).toBeNull();

    await user.click(screen.getByRole("button", { name: "Archivados" }));
    expect(await screen.findByText("Peinado antiguo")).toBeTruthy();
    expect(screen.queryByText("Corte clásico")).toBeNull();
    expect(backend.listQueries.some((query) => query.includes("archived=true"))).toBe(true);

    await user.click(screen.getByRole("button", { name: "Restaurar Peinado antiguo" }));

    await waitFor(() => expect(backend.restored).toEqual(["s3"]));
    await waitFor(() => expect(screen.queryByText("Peinado antiguo")).toBeNull());
    await user.click(screen.getByRole("button", { name: "Activos" }));
    expect(await screen.findByText("Peinado antiguo")).toBeTruthy();
  });

  it("el chip Archivados solo aparece con service.manage (gate)", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist", permissions: READER_PERMISSIONS }) });
    servicesBackend({ services: [corte] });
    await openServices();

    expect(await screen.findByRole("button", { name: "Pausados" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Archivados" })).toBeNull();
  });

  it("un servicio archivado abre el panel de solo lectura, sin override, y solo ofrece Restaurar", async () => {
    asManager();
    const backend = servicesBackend({
      services: [viejo],
      overrides: [serviceOverride("o3", "s3", ids.branchA, { duration_minutes: 10 })],
    });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Archivados" }));
    await user.click(await screen.findByRole("button", { name: "Ver Peinado antiguo" }));
    const panel = await screen.findByRole("complementary", { name: "Peinado antiguo" });

    expect(within(panel).queryByRole("textbox")).toBeNull();
    expect(within(panel).queryByRole("button", { name: "Editar servicio" })).toBeNull();
    expect(within(panel).queryByRole("region", { name: "En Sucursal Centro" })).toBeNull();

    await user.click(within(panel).getByRole("button", { name: "Restaurar" }));
    await waitFor(() => expect(backend.restored).toEqual(["s3"]));
    await waitFor(() => expect(screen.queryByRole("complementary")).toBeNull());
  });

  it("el Restaurar del panel se deshabilita mientras la restauración está en curso", async () => {
    asManager();
    servicesBackend({ services: [viejo] });
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    let calls = 0;
    server.use(
      http.post(`${CATALOG}/appointments/services/:id/restore`, async () => {
        calls += 1;
        await gate;
        return HttpResponse.json({ data: { ...viejo, archived_at: null } });
      }),
    );
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Archivados" }));
    await user.click(await screen.findByRole("button", { name: "Ver Peinado antiguo" }));
    const panel = await screen.findByRole("complementary", { name: "Peinado antiguo" });
    await user.click(within(panel).getByRole("button", { name: "Restaurar" }));

    await waitFor(() =>
      expect(within(panel).getByRole("button", { name: "Restaurar" })).toHaveProperty(
        "disabled",
        true,
      ),
    );
    await user.click(within(panel).getByRole("button", { name: "Restaurar" }));
    release();
    await waitFor(() =>
      expect(within(panel).getByRole("button", { name: "Restaurar" })).toHaveProperty(
        "disabled",
        false,
      ),
    );
    expect(calls).toBe(1);
  });

  it("Pausados lista solo los no activos y Archivar saca el servicio de Activos", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte, tinte] });
    const { user } = await openServices();

    await screen.findByText("Corte clásico");
    expect(screen.queryByText("Tinte")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Pausados" }));
    expect(await screen.findByText("Tinte")).toBeTruthy();
    expect(screen.queryByText("Corte clásico")).toBeNull();

    await user.click(screen.getByRole("button", { name: "Activos" }));
    await user.click(await screen.findByRole("button", { name: "Archivar Corte clásico" }));

    await waitFor(() => expect(backend.archived).toEqual(["s1"]));
    await waitFor(() => expect(screen.queryByText("Corte clásico")).toBeNull());
  });

  it("una fila abre su detalle; 'Editar servicio' abre el modal precargado y guarda por PATCH", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte] });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Ver Corte clásico" }));
    const panel = await screen.findByRole("complementary", { name: "Corte clásico" });
    expect(panel.closest("[data-variant=floating]")).not.toBeNull();
    await user.click(within(panel).getByRole("button", { name: "Editar servicio" }));

    const dialog = await screen.findByRole("dialog", { name: "Editar servicio" });
    expect(within(dialog).getByLabelText("Precio (NIO)")).toHaveProperty("value", "200.00");
    const name = within(dialog).getByLabelText("Nombre");
    await user.clear(name);
    await user.type(name, "Corte premium");
    expect(within(dialog).getAllByRole("button", { name: /guardar/i })).toHaveLength(1);
    await user.click(within(dialog).getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(backend.patched).toHaveLength(1));
    expect(backend.patched[0]).toEqual({
      id: "s1",
      body: {
        name: "Corte premium",
        category: null,
        duration_minutes: 30,
        buffer_before_minutes: 0,
        buffer_after_minutes: 0,
        price_minor: 20000,
        active: true,
      },
    });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });

  it("crea un servicio en el modal con su categoría y la duración elegida con los botones", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte] });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Nuevo servicio" }));
    const dialog = await screen.findByRole("dialog", { name: "Nuevo servicio" });
    await user.type(within(dialog).getByLabelText("Nombre"), "Barba");
    await user.type(
      within(dialog).getByRole("combobox", { name: "Categoría (opcional)" }),
      "Barbería",
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Restar 5 minutos a la duración" }),
    );
    await user.type(within(dialog).getByLabelText("Precio (NIO)"), "120.5");
    await user.click(within(dialog).getByRole("button", { name: "Crear servicio" }));

    await waitFor(() => expect(backend.created).toHaveLength(1));
    expect(backend.created[0]).toEqual({
      name: "Barba",
      category: "Barbería",
      duration_minutes: 25,
      buffer_before_minutes: 0,
      buffer_after_minutes: 0,
      price_minor: 12050,
      active: true,
      position: 0,
    });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(await screen.findByRole("button", { name: "Ver Barba" })).toBeTruthy();
  });

  it("el modal sugiere las categorías de los servicios cargados, sin repetirlas", async () => {
    asManager();
    servicesBackend({
      services: [
        corte,
        service("s4", "Corte niño", { category: "Cortes" }),
        service("s5", "Afeitado", { category: "Barba" }),
      ],
    });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Nuevo servicio" }));
    const dialog = await screen.findByRole("dialog", { name: "Nuevo servicio" });
    await user.click(within(dialog).getByRole("combobox", { name: "Categoría (opcional)" }));

    const list = within(dialog).getByRole("listbox", { name: "Categorías usadas" });
    expect(
      within(list)
        .getAllByRole("option")
        .map((option) => option.textContent),
    ).toEqual(["Barba", "Cortes"]);
  });

  describe("recepción en lectura (AC8)", () => {
    const asReception = () =>
      signedInBackend({ me: meFixture({ role: "receptionist", permissions: READER_PERMISSIONS }) });

    it("sin crear, sin acciones por fila, con aviso de solo lectura; la fila abre el detalle flotante y no un modal", async () => {
      asReception();
      servicesBackend({ services: [{ ...corte, category: "Cortes" }] });
      const { user } = await openServices();

      expect(await screen.findByText("Solo lectura")).toBeTruthy();
      expect(screen.queryByRole("button", { name: "Nuevo servicio" })).toBeNull();
      expect(screen.queryByRole("columnheader", { name: "Acciones" })).toBeNull();
      expect(screen.queryByRole("button", { name: /Archivar/ })).toBeNull();

      await user.click(screen.getByRole("button", { name: "Ver Corte clásico" }));
      const panel = await screen.findByRole("complementary", { name: "Corte clásico" });

      expect(panel.closest("[data-variant=floating]")).not.toBeNull();
      expect(within(panel).getByText("Cortes")).toBeTruthy();
      expect(within(panel).getAllByText("30 min").length).toBeGreaterThan(0);
      expect(within(panel).queryByRole("textbox")).toBeNull();
      expect(
        within(panel).queryByText(
          "Duración y precio propios de esta sucursal. Si los deja vacíos, se usa lo del servicio.",
        ),
      ).toBeNull();
      expect(within(panel).queryByRole("button", { name: /Editar|Guardar/ })).toBeNull();
      expect(document.querySelectorAll("[data-slot=form-description]")).toHaveLength(0);
      expect(screen.queryByRole("dialog")).toBeNull();
    });
  });

  describe("override por sucursal (AC2)", () => {
    const asBranchManager = () =>
      signedInBackend({
        me: meFixture({ role: "receptionist", permissions: BRANCH_MANAGER_PERMISSIONS }),
      });

    it("el gerente de sucursal edita la duración y ve el precio como texto; el PUT lleva solo duration_minutes", async () => {
      asBranchManager();
      const backend = servicesBackend({
        services: [corte],
        overrides: [serviceOverride("o1", "s1", ids.branchA, { price_minor: 25000 })],
      });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Ver Corte clásico" }));
      const panel = await screen.findByRole("complementary", { name: "Corte clásico" });
      const override = await within(panel).findByRole("region", { name: "En Sucursal Centro" });

      expect(within(override).queryByRole("textbox", { name: /Precio/ })).toBeNull();
      expect(within(override).getByText(/250\.00/)).toBeTruthy();
      // The service itself is read-only for this role.
      expect(within(panel).queryByRole("button", { name: "Editar servicio" })).toBeNull();

      await user.type(within(override).getByLabelText("Duración en esta sucursal (minutos)"), "45");
      await user.click(
        within(override).getByRole("button", { name: "Guardar para esta sucursal" }),
      );

      await waitFor(() => expect(backend.overridePuts).toHaveLength(1));
      expect(backend.overridePuts[0]).toEqual({ serviceId: "s1", body: { duration_minutes: 45 } });
    });

    it("service.manage sin claves de override NO edita el override (el gate espeja la política): duración y precio quedan como texto", async () => {
      signedInBackend({
        me: meFixture({
          role: "company_manager",
          permissions: [
            "appointments.service.read",
            "appointments.service.manage",
            "appointments.schedule.read",
          ],
        }),
      });
      servicesBackend({
        services: [corte],
        overrides: [
          serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 40, price_minor: 25000 }),
        ],
      });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Ver Corte clásico" }));
      const panel = await screen.findByRole("complementary", { name: "Corte clásico" });
      const override = await within(panel).findByRole("region", { name: "En Sucursal Centro" });

      expect(within(override).queryByLabelText(/Duración en esta sucursal/)).toBeNull();
      expect(within(override).queryByLabelText(/Precio en esta sucursal/)).toBeNull();
      expect(within(override).queryByRole("button", { name: /Quitar personalización/ })).toBeNull();
    });

    it("si la API responde 403 al guardar el override, el error se muestra", async () => {
      asBranchManager();
      servicesBackend({ services: [corte], overrideForbidden: true });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Ver Corte clásico" }));
      const override = await screen.findByRole("region", { name: "En Sucursal Centro" });
      await user.type(within(override).getByLabelText("Duración en esta sucursal (minutos)"), "45");
      await user.click(
        within(override).getByRole("button", { name: "Guardar para esta sucursal" }),
      );

      expect((await within(override).findByRole("alert")).textContent).toContain(
        "Su rol no incluye esta sección",
      );
    });

    it("el gerente de empresa edita duración y precio (los dos inputs) y quita la personalización", async () => {
      asManager();
      const backend = servicesBackend({
        services: [corte],
        overrides: [serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 40 })],
      });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Ver Corte clásico" }));
      const override = await screen.findByRole("region", { name: "En Sucursal Centro" });

      expect(within(override).getByLabelText("Precio en esta sucursal (NIO)")).toBeTruthy();
      await user.click(within(override).getByRole("button", { name: "Quitar personalización" }));

      await waitFor(() => expect(backend.overrideDeletes).toEqual(["s1"]));
    });

    it("con «Todas las sucursales» muestra los valores base de la empresa, sin sección de override ni selector propio", async () => {
      signedInBackend({
        me: meFixture({ role: "company_manager", permissions: MANAGER_PERMISSIONS, branch: null }),
        branches: [
          branch(ids.branchA, ids.companyA, "Sucursal Centro"),
          branch(ids.branchA2, ids.companyA, "Sucursal Norte"),
        ],
      });
      servicesBackend({
        services: [corte],
        overrides: [serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 50 })],
      });
      const { user } = await openServices();

      const row = (await screen.findByText("Corte clásico")).closest("tr")!;
      expect(within(row).getByText("30 min")).toBeTruthy();
      expect(screen.queryByRole("combobox")).toBeNull();

      await user.click(screen.getByRole("button", { name: "Ver Corte clásico" }));
      await screen.findByRole("complementary", { name: "Corte clásico" });
      expect(screen.queryByRole("region", { name: /^En / })).toBeNull();
    });
  });
});
