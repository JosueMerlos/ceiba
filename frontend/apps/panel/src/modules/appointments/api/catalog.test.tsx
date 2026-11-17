import { ApiClientProvider, createApiClient, createCsrfStore } from "@ceiba/api-client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import { MeProvider } from "../../../platform/me/me-provider";
import {
  API,
  branch,
  ids,
  meFixture,
  scheduleSlot,
  service,
  serviceOverride,
  validationProblem,
} from "../../../test/fixtures";
import { server } from "../../../test/server";
import {
  catalogKeys,
  useArchiveService,
  useBranchScheduleQuery,
  useCompanyBranchesQuery,
  useCreateBranch,
  usePutBranchSchedule,
  usePutServiceOverride,
  useRestoreService,
  useServiceOverridesQuery,
  useServicesQuery,
} from "./catalog";

const BASE = `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}`;
const page = (data: unknown[]) => ({ data, page: { has_more: false, next_cursor: null } });

function setup() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const client = createApiClient({ baseUrl: API, csrf: createCsrfStore() });
  const me = meFixture({ role: "company_manager" }).data;
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      <ApiClientProvider client={client}>
        <MeProvider me={me}>{children}</MeProvider>
      </ApiClientProvider>
    </QueryClientProvider>
  );
  return { queryClient, wrapper };
}

describe("claves de caché", () => {
  it("incluyen organización, empresa y sucursal: otra empresa no comparte caché (adversarial)", () => {
    expect(catalogKeys.services(ids.orgA, ids.companyA, "active")).not.toEqual(
      catalogKeys.services(ids.orgA, ids.companyA2, "active"),
    );
    expect(catalogKeys.services(ids.orgA, ids.companyA, "active")).not.toEqual(
      catalogKeys.services(ids.orgA, ids.companyA, "archived"),
    );
    expect(catalogKeys.overrides(ids.orgA, ids.companyA, ids.branchA)).not.toEqual(
      catalogKeys.overrides(ids.orgA, ids.companyA, ids.branchA2),
    );
    expect(catalogKeys.schedule(ids.orgA, ids.companyA, ids.branchA)).toContain(ids.branchA);
  });
});

describe("servicios", () => {
  const listUrls: string[] = [];
  const listHandler = () =>
    http.get(`${BASE}/appointments/services`, ({ request }) => {
      listUrls.push(new URL(request.url).search);
      return HttpResponse.json(page([service("s1", "Corte")]));
    });

  it.each([
    ["active", "archived=false&active=true"],
    ["paused", "archived=false&active=false"],
    ["archived", "archived=true"],
  ] as const)("el filtro %s pide ?%s", async (filter, expected) => {
    listUrls.length = 0;
    server.use(listHandler());
    const { wrapper } = setup();

    const { result } = renderHook(() => useServicesQuery(filter), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    const query = new URLSearchParams(listUrls[0]);
    expect(query.get("archived")).toBe(new URLSearchParams(expected).get("archived"));
    expect(query.get("active")).toBe(new URLSearchParams(expected).get("active"));
    expect(result.current.data?.data[0]?.name).toBe("Corte");
  });

  it("archivar hace DELETE del servicio y refresca todas las listas de servicios", async () => {
    const deleted = vi.fn();
    let lists = 0;
    server.use(
      http.get(`${BASE}/appointments/services`, () => {
        lists += 1;
        return HttpResponse.json(page([]));
      }),
      http.delete(`${BASE}/appointments/services/:id`, ({ params }) => {
        deleted(params.id);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    const { wrapper } = setup();
    const { result } = renderHook(
      () => ({ list: useServicesQuery("active"), archive: useArchiveService() }),
      {
        wrapper,
      },
    );
    await waitFor(() => expect(result.current.list.isSuccess).toBe(true));

    await act(() => result.current.archive.mutateAsync("s1"));

    expect(deleted).toHaveBeenCalledWith("s1");
    await waitFor(() => expect(lists).toBe(2));
  });

  it("restaurar hace POST a /restore", async () => {
    const restored = vi.fn();
    server.use(
      http.post(`${BASE}/appointments/services/:id/restore`, ({ params }) => {
        restored(params.id);
        return HttpResponse.json({ data: service("s1", "Corte") });
      }),
    );
    const { wrapper } = setup();
    const { result } = renderHook(() => useRestoreService(), { wrapper });

    await act(() => result.current.mutateAsync("s1"));

    expect(restored).toHaveBeenCalledWith("s1");
  });
});

describe("overrides", () => {
  it("lista los de la sucursal y el PUT envía exactamente el cuerpo recibido", async () => {
    const bodies: unknown[] = [];
    server.use(
      http.get(`${BASE}/appointments/branches/${ids.branchA}/service_overrides`, () =>
        HttpResponse.json(
          page([serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 45 })]),
        ),
      ),
      http.put(
        `${BASE}/appointments/branches/${ids.branchA}/services/s1/override`,
        async ({ request }) => {
          bodies.push(await request.json());
          return HttpResponse.json({
            data: serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 50 }),
          });
        },
      ),
    );
    const { wrapper } = setup();
    const { result } = renderHook(
      () => ({
        list: useServiceOverridesQuery(ids.branchA),
        put: usePutServiceOverride(ids.branchA),
      }),
      { wrapper },
    );
    await waitFor(() => expect(result.current.list.data?.data).toHaveLength(1));

    await act(() =>
      result.current.put.mutateAsync({ serviceId: "s1", body: { duration_minutes: 50 } }),
    );

    expect(bodies).toEqual([{ duration_minutes: 50 }]);
  });

  it("sin sucursal no pide nada (adversarial: nunca arma la URL con undefined)", async () => {
    const { wrapper } = setup();

    const { result } = renderHook(() => useServiceOverridesQuery(undefined), { wrapper });

    expect(result.current.fetchStatus).toBe("idle");
  });
});

describe("sucursales y horario", () => {
  it("crear sucursal hace POST con el cuerpo y refresca la lista de sucursales", async () => {
    const bodies: unknown[] = [];
    let lists = 0;
    server.use(
      http.get(`${BASE}/branches`, () => {
        lists += 1;
        return HttpResponse.json(page([]));
      }),
      http.post(`${BASE}/branches`, async ({ request }) => {
        bodies.push(await request.json());
        return HttpResponse.json(
          { data: branch("nueva", ids.companyA, "Granada") },
          { status: 201 },
        );
      }),
    );
    const { wrapper } = setup();
    const { result } = renderHook(
      () => ({ create: useCreateBranch(), list: useCompanyBranchesQuery() }),
      { wrapper },
    );
    await waitFor(() => expect(result.current.list.isSuccess).toBe(true));

    const created = await act(() =>
      result.current.create.mutateAsync({ name: "Granada", time_zone: "America/Managua" }),
    );

    expect(bodies).toEqual([{ name: "Granada", time_zone: "America/Managua" }]);
    expect(created.data.id).toBe("nueva");
    await waitFor(() => expect(lists).toBe(2));
  });

  it("el PUT del horario manda las franjas y el 422 llega como ApiError con el campo slots", async () => {
    server.use(
      http.get(`${BASE}/appointments/branches/${ids.branchA}/schedule`, () =>
        HttpResponse.json({ data: [scheduleSlot("x", 1, "09:00", "13:00")] }),
      ),
      http.put(`${BASE}/appointments/branches/${ids.branchA}/schedule`, () =>
        HttpResponse.json(validationProblem("slots", "overlap", "franjas solapadas"), {
          status: 422,
        }),
      ),
    );
    const { wrapper } = setup();
    const { result } = renderHook(
      () => ({ read: useBranchScheduleQuery(ids.branchA), put: usePutBranchSchedule(ids.branchA) }),
      { wrapper },
    );
    await waitFor(() => expect(result.current.read.data?.data).toHaveLength(1));

    await expect(act(() => result.current.put.mutateAsync({ slots: [] }))).rejects.toMatchObject({
      status: 422,
      errors: [{ field: "slots" }],
    });
  });
});
