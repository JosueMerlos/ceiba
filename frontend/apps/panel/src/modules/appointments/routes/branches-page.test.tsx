import { screen, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import {
  BRANCH_MANAGER_PERMISSIONS,
  CATALOG,
  MANAGER_PERMISSIONS,
  page,
} from "../../../test/catalog-backend";
import {
  API,
  branch,
  ids,
  meFixture,
  problem,
  scheduleSlot,
  validationProblem,
} from "../../../test/fixtures";
import { renderApp } from "../../../test/render-app";
import { server, signedInBackend } from "../../../test/server";

const centro = branch(ids.branchA, ids.companyA, "Sucursal Centro");
const norte = branch(ids.branchA2, ids.companyA, "Sucursal Norte");

function branchesBackend({
  schedules = {} as Record<string, unknown[]>,
  forbiddenSchedule = [] as string[],
} = {}) {
  const state = { created: [] as unknown[], branches: [centro, norte] };
  server.use(
    http.get(`${CATALOG}/branches`, () => HttpResponse.json(page(state.branches))),
    http.post(`${CATALOG}/branches`, async ({ request }) => {
      const body = (await request.json()) as { name: string; time_zone: string };
      state.created.push(body);
      const created = {
        ...branch("0198f0a0-0000-7000-8000-00000000ab01", ids.companyA, body.name),
        time_zone: body.time_zone,
      };
      state.branches = [...state.branches, created];
      return HttpResponse.json({ data: created }, { status: 201 });
    }),
    http.get(`${CATALOG}/appointments/branches/:branchId/schedule`, ({ params }) => {
      const id = String(params.branchId);
      if (forbiddenSchedule.includes(id)) {
        return HttpResponse.json(problem(404, "resource.not_found", "No encontrado"), {
          status: 404,
        });
      }
      return HttpResponse.json({ data: schedules[id] ?? [] });
    }),
  );
  return state;
}

const asManager = (extra: Parameters<typeof meFixture>[0] = {}) =>
  signedInBackend({
    me: meFixture({ role: "company_manager", permissions: MANAGER_PERMISSIONS, ...extra }),
    branches: [centro, norte],
  });

describe("Sucursales", () => {
  it("lista las sucursales con su estado de horario: con horario o cerrada", async () => {
    asManager();
    branchesBackend({ schedules: { [ids.branchA]: [scheduleSlot("x", 1, "09:00", "17:00")] } });
    await renderApp({ route: "/branches" });

    const centroRow = await screen.findByRole("row", { name: /Sucursal Centro/ });
    const norteRow = screen.getByRole("row", { name: /Sucursal Norte/ });
    await waitFor(() => expect(within(centroRow).getByText("Con horario")).toBeTruthy());
    expect(within(norteRow).getByText("Cerrada: sin horario")).toBeTruthy();
    expect(within(centroRow).getByText("America/Managua")).toBeTruthy();
    expect(
      within(norteRow)
        .getByRole("link", { name: "Horario de Sucursal Norte" })
        .getAttribute("href"),
    ).toBe(`/branches/${ids.branchA2}/schedule`);
  });

  it("sin permiso para leer el horario de una sucursal (404) la lista sigue en pie y no inventa el estado", async () => {
    asManager();
    branchesBackend({ forbiddenSchedule: [ids.branchA2] });
    await renderApp({ route: "/branches" });

    const norteRow = await screen.findByRole("row", { name: /Sucursal Norte/ });
    await waitFor(() =>
      expect(
        within(screen.getByRole("row", { name: /Sucursal Centro/ })).getByText(
          "Cerrada: sin horario",
        ),
      ).toBeTruthy(),
    );
    expect(within(norteRow).queryByText("Cerrada: sin horario")).toBeNull();
    expect(within(norteRow).queryByText("Con horario")).toBeNull();
  });

  it("sin platform.branch.create no hay botón 'Nueva sucursal' (gate)", async () => {
    signedInBackend({
      me: meFixture({ role: "receptionist", permissions: BRANCH_MANAGER_PERMISSIONS }),
      branches: [centro],
    });
    branchesBackend();
    await renderApp({ route: "/branches" });

    await screen.findByRole("row", { name: /Sucursal Centro/ });
    expect(screen.queryByRole("button", { name: "Nueva sucursal" })).toBeNull();
  });

  it("AC5: crear una sucursal navega a su horario, que aparece cerrado hasta configurarlo", async () => {
    asManager();
    const backend = branchesBackend();
    const { user, app } = await renderApp({ route: "/branches" });

    await user.click(await screen.findByRole("button", { name: "Nueva sucursal" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva sucursal" });
    await user.type(within(panel).getByLabelText("Nombre"), "Granada");
    await user.click(within(panel).getByRole("button", { name: "Crear sucursal" }));

    await waitFor(() =>
      expect(backend.created).toEqual([{ name: "Granada", time_zone: "America/Managua" }]),
    );
    await waitFor(() =>
      expect(app.router.state.location.pathname).toBe(
        "/branches/0198f0a0-0000-7000-8000-00000000ab01/schedule",
      ),
    );
    expect(
      await screen.findByRole("heading", {
        name: "Configure el horario: la sucursal está cerrada hasta entonces",
      }),
    ).toBeTruthy();
  });

  it("el formulario de alta propone la zona horaria de la sucursal en contexto", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        permissions: MANAGER_PERMISSIONS,
        branch: { ...centro, time_zone: "America/Costa_Rica" },
      }),
      branches: [centro],
    });
    branchesBackend();
    const { user } = await renderApp({ route: "/branches" });

    await user.click(await screen.findByRole("button", { name: "Nueva sucursal" }));

    expect((await screen.findByRole("combobox", { name: "Zona horaria" })).textContent).toContain(
      "America/Costa_Rica",
    );
  });

  it("un 422 de la API se muestra en el formulario y no navega", async () => {
    asManager();
    branchesBackend();
    server.use(
      http.post(`${CATALOG}/branches`, () =>
        HttpResponse.json(
          validationProblem("name", "taken", "ya existe una sucursal con ese nombre"),
          { status: 422 },
        ),
      ),
    );
    const { user, app } = await renderApp({ route: "/branches" });

    await user.click(await screen.findByRole("button", { name: "Nueva sucursal" }));
    const panel = await screen.findByRole("complementary", { name: "Nueva sucursal" });
    await user.type(within(panel).getByLabelText("Nombre"), "Centro");
    await user.click(within(panel).getByRole("button", { name: "Crear sucursal" }));

    expect(await screen.findByText("ya existe una sucursal con ese nombre")).toBeTruthy();
    expect(app.router.state.location.pathname).toBe("/branches");
  });
});

void API;
