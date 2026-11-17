import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import {
  BRANCH_MANAGER_PERMISSIONS,
  MANAGER_PERMISSIONS,
  READER_PERMISSIONS,
  servicesBackend,
} from "../../../test/catalog-backend";
import { branch, ids, meFixture, service, serviceOverride } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { signedInBackend } from "../../../test/server";

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
  it("sin servicios muestra 'Agregue su primer servicio' y la acción abre el panel de alta", async () => {
    asManager();
    servicesBackend();
    const { user } = await openServices();

    expect(await screen.findByRole("heading", { name: "Agregue su primer servicio" })).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar servicio" }));

    expect(await screen.findByRole("complementary", { name: "Nuevo servicio" })).toBeTruthy();
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

  it("seleccionar una fila abre el panel con la edición y guarda por PATCH", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte] });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
    const panel = await screen.findByRole("complementary", { name: "Corte clásico" });
    expect(within(panel).getByLabelText("Precio (NIO)")).toHaveProperty("value", "200.00");

    const name = within(panel).getByLabelText("Nombre");
    await user.clear(name);
    await user.type(name, "Corte premium");
    await user.click(within(panel).getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(backend.patched).toHaveLength(1));
    expect(backend.patched[0]).toEqual({
      id: "s1",
      body: {
        name: "Corte premium",
        duration_minutes: 30,
        buffer_after_minutes: 0,
        price_minor: 20000,
        active: true,
      },
    });
  });

  it("crea un servicio nuevo con precio en unidades menores y lo muestra en la lista", async () => {
    asManager();
    const backend = servicesBackend({ services: [corte] });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Nuevo servicio" }));
    const panel = await screen.findByRole("complementary", { name: "Nuevo servicio" });
    await user.type(within(panel).getByLabelText("Nombre"), "Barba");
    await user.type(within(panel).getByLabelText("Duración (minutos)"), "20");
    await user.type(within(panel).getByLabelText("Precio (NIO)"), "120.5");
    await user.click(within(panel).getByRole("button", { name: "Crear servicio" }));

    await waitFor(() => expect(backend.created).toHaveLength(1));
    expect(backend.created[0]).toEqual({
      name: "Barba",
      duration_minutes: 20,
      buffer_after_minutes: 0,
      buffer_before_minutes: 0,
      price_minor: 12050,
      active: true,
      position: 0,
    });
    expect(await screen.findByRole("button", { name: "Editar Barba" })).toBeTruthy();
  });

  it("sin service.manage el panel queda de solo lectura y no hay Archivar (gate)", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist", permissions: READER_PERMISSIONS }) });
    servicesBackend({ services: [corte] });
    const { user } = await openServices();

    await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
    const panel = await screen.findByRole("complementary", { name: "Corte clásico" });

    expect(within(panel).getByLabelText("Nombre")).toHaveProperty("disabled", true);
    expect(within(panel).queryByRole("button", { name: "Guardar cambios" })).toBeNull();
    expect(screen.queryByRole("button", { name: /Archivar/ })).toBeNull();
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

      await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
      const panel = await screen.findByRole("complementary", { name: "Corte clásico" });
      const override = await within(panel).findByRole("region", { name: "En Sucursal Centro" });

      expect(within(override).queryByRole("textbox", { name: /Precio/ })).toBeNull();
      expect(within(override).getByText(/250\.00/)).toBeTruthy();
      // The service itself is read-only for this role.
      expect(within(panel).getByLabelText("Nombre")).toHaveProperty("disabled", true);

      await user.type(within(override).getByLabelText("Duración en esta sucursal (minutos)"), "45");
      await user.click(
        within(override).getByRole("button", { name: "Guardar para esta sucursal" }),
      );

      await waitFor(() => expect(backend.overridePuts).toHaveLength(1));
      expect(backend.overridePuts[0]).toEqual({ serviceId: "s1", body: { duration_minutes: 45 } });
    });

    it("si la API responde 403 al guardar el override, el error se muestra", async () => {
      asBranchManager();
      servicesBackend({ services: [corte], overrideForbidden: true });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
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

      await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
      const override = await screen.findByRole("region", { name: "En Sucursal Centro" });

      expect(within(override).getByLabelText("Precio en esta sucursal (NIO)")).toBeTruthy();
      await user.click(within(override).getByRole("button", { name: "Quitar personalización" }));

      await waitFor(() => expect(backend.overrideDeletes).toEqual(["s1"]));
    });

    it("sin sucursal en el contexto la pantalla pide elegir una y solo entonces muestra el override", async () => {
      signedInBackend({
        me: meFixture({ role: "company_manager", permissions: MANAGER_PERMISSIONS, branch: null }),
        branches: [
          branch(ids.branchA, ids.companyA, "Sucursal Centro"),
          branch(ids.branchA2, ids.companyA, "Sucursal Norte"),
        ],
      });
      servicesBackend({ services: [corte] });
      const { user } = await openServices();

      await user.click(await screen.findByRole("button", { name: "Editar Corte clásico" }));
      await screen.findByRole("complementary", { name: "Corte clásico" });
      expect(screen.queryByRole("region", { name: /^En / })).toBeNull();

      await user.click(screen.getByRole("combobox", { name: "Sucursal de trabajo" }));
      await user.click(await screen.findByRole("option", { name: "Sucursal Norte" }));

      expect(await screen.findByRole("region", { name: "En Sucursal Norte" })).toBeTruthy();
    });
  });
});
