import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { branch, ids, meFixture, resource, scheduleSlot, timeOff } from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { signedInBackend } from "../../../test/server";
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
    expect(await screen.findByRole("complementary", { name: "Nuevo recurso" })).toBeTruthy();
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

  it("crea un recurso en la sucursal de trabajo y queda en la lista", async () => {
    asManager();
    const backend = staffBackend({ resources: [sillon] });
    const { user } = await openResources();

    await user.click(await screen.findByRole("button", { name: "Nuevo recurso" }));
    const panel = await screen.findByRole("complementary", { name: "Nuevo recurso" });
    await user.type(within(panel).getByLabelText("Nombre"), "Camilla 1");
    await user.click(within(panel).getByRole("combobox", { name: "Tipo" }));
    await user.click(await screen.findByRole("option", { name: "Equipo" }));
    await user.click(within(panel).getByRole("button", { name: "Crear recurso" }));

    await waitFor(() => expect(backend.createdResources).toHaveLength(1));
    expect(backend.createdResources[0]).toEqual({
      branchId: ids.branchA,
      body: { name: "Camilla 1", kind: "equipment", active: true },
    });
    expect(await screen.findByRole("button", { name: "Editar Camilla 1" })).toBeTruthy();
  });

  it("edita un recurso por PATCH y lo archiva desde la tabla", async () => {
    asManager();
    const backend = staffBackend({ resources: [sillon] });
    const { user } = await openResources();

    await user.click(await screen.findByRole("button", { name: "Editar Sillón 1" }));
    const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
    await user.click(within(panel).getByRole("switch", { name: "Disponible" }));
    await user.click(within(panel).getByRole("button", { name: "Guardar cambios" }));
    await waitFor(() => expect(backend.patchedResources).toHaveLength(1));
    expect(backend.patchedResources[0]).toEqual({
      id: "r1",
      body: { name: "Sillón 1", kind: "chair", active: false },
    });

    await user.click(screen.getByRole("button", { name: "Archivar Sillón 1" }));
    await waitFor(() => expect(backend.archivedResources).toEqual(["r1"]));
  });

  it("horario del recurso: edita y guarda con PUT", async () => {
    asManager();
    const backend = staffBackend({
      resources: [sillon],
      schedules: { r1: [scheduleSlot("sl1", 2, "09:00", "13:00")] },
    });
    const { user } = await openResources();

    await user.click(await screen.findByRole("button", { name: "Editar Sillón 1" }));
    const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
    const section = await within(panel).findByRole("region", { name: "Horario semanal" });
    const tuesday = await within(section).findByRole("group", { name: "Martes" });
    await user.click(within(tuesday).getByRole("button", { name: "Agregar franja" }));
    await user.click(within(section).getByRole("button", { name: "Guardar horario" }));

    await waitFor(() => expect(backend.schedulePuts).toHaveLength(1));
    expect(backend.schedulePuts[0]!.owner).toBe("r1");
  });

  it("ausencias del recurso: crea con la hora local convertida a UTC y quita otra", async () => {
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

    await user.click(await screen.findByRole("button", { name: "Editar Sillón 1" }));
    const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
    const section = await within(panel).findByRole("region", { name: "Ausencias" });
    expect(await within(section).findByText("Mantenimiento")).toBeTruthy();

    fireEvent.change(within(section).getByLabelText("Desde"), {
      target: { value: "2026-12-02T08:00" },
    });
    fireEvent.change(within(section).getByLabelText("Hasta"), {
      target: { value: "2026-12-02T09:00" },
    });
    await user.click(within(section).getByRole("button", { name: "Agregar ausencia" }));
    await waitFor(() => expect(backend.createdTimeOffs).toHaveLength(1));
    expect(backend.createdTimeOffs[0]!.body).toEqual({
      starts_at: "2026-12-02T14:00:00.000Z",
      ends_at: "2026-12-02T15:00:00.000Z",
      reason: null,
    });

    await user.click(within(section).getAllByRole("button", { name: /^Quitar ausencia/ })[0]!);
    await waitFor(() => expect(backend.deletedTimeOffs).toEqual([{ owner: "r1", id: "t1" }]));
  });

  it("sin sucursal en el contexto y con varias pide elegir una antes de listar (adversarial)", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: STAFF_MANAGER_PERMISSIONS,
        branch: null,
      }),
      branches: [centro, norte],
    });
    staffBackend({ resources: [sillon] });
    const { user } = await openResources();

    expect(await screen.findByRole("combobox", { name: "Sucursal de trabajo" })).toBeTruthy();
    expect(screen.queryByText("Sillón 1")).toBeNull();
    await user.click(screen.getByRole("combobox", { name: "Sucursal de trabajo" }));
    await user.click(await screen.findByRole("option", { name: "Sucursal Centro" }));
    expect(await screen.findByText("Sillón 1")).toBeTruthy();
  });

  it("un lector abre el panel sin editar: ni guardar, ni agregar ausencias, ni quitarlas (gate)", async () => {
    asManager(STAFF_READER_PERMISSIONS);
    staffBackend({ resources: [sillon] });
    const { user } = await openResources();

    await user.click(await screen.findByRole("button", { name: "Editar Sillón 1" }));
    const panel = await screen.findByRole("complementary", { name: "Sillón 1" });
    expect(within(panel).getByLabelText("Nombre")).toHaveProperty("disabled", true);
    expect(within(panel).queryByRole("button", { name: "Guardar cambios" })).toBeNull();
    const section = await within(panel).findByRole("region", { name: "Ausencias" });
    expect(within(section).queryByLabelText("Desde")).toBeNull();
    expect(screen.queryByRole("button", { name: /Archivar/ })).toBeNull();
  });
});
