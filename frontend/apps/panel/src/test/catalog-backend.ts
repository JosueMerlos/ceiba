import type { components } from "@ceiba/api-client";
import { http, HttpResponse } from "msw";
import { API, ids, service, serviceOverride, validationProblem } from "./fixtures";
import { server } from "./server";

type Service = components["schemas"]["Service"];
type Override = components["schemas"]["ServiceOverride"];

export const CATALOG = `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}`;
export const page = (data: unknown[]) => ({ data, page: { has_more: false, next_cursor: null } });

export const MANAGER_PERMISSIONS = [
  "appointments.service.read",
  "appointments.service.manage",
  "appointments.service.override_duration",
  "appointments.service.override_price",
  "appointments.schedule.read",
  "appointments.schedule.manage",
  "platform.branch.create",
];

// A branch manager: reads the catalog, changes the duration per branch (not the price) and manages the branch hours.
export const BRANCH_MANAGER_PERMISSIONS = [
  "appointments.service.read",
  "appointments.service.override_duration",
  "appointments.schedule.read",
  "appointments.schedule.manage",
];

export const READER_PERMISSIONS = ["appointments.service.read", "appointments.schedule.read"];

interface ServicesBackendOptions {
  services?: Service[];
  overrides?: Override[];
  /** Makes PUT override answer 403 (a role the API refuses even though the UI offered the field). */
  overrideForbidden?: boolean;
  /** Serves the list in pages of this size with a real cursor (`has_more`/`next_cursor`, `?after=`). */
  pageSize?: number;
}

/** In-memory services API: lists honor ?archived/?active; every mutation is recorded for assertions. */
export function servicesBackend({
  services = [],
  overrides = [],
  overrideForbidden = false,
  pageSize,
}: ServicesBackendOptions = {}) {
  const state = {
    services: [...services],
    listQueries: [] as string[],
    created: [] as unknown[],
    patched: [] as { id: string; body: unknown }[],
    archived: [] as string[],
    restored: [] as string[],
    overridePuts: [] as { serviceId: string; body: unknown }[],
    overrideDeletes: [] as string[],
  };

  server.use(
    http.get(`${CATALOG}/appointments/services`, ({ request }) => {
      const query = new URL(request.url).searchParams;
      state.listQueries.push(query.toString());
      const archived = query.get("archived") === "true";
      const active = query.get("active");
      const data = state.services.filter(
        (item) =>
          (item.archived_at !== null) === archived &&
          (active === null || String(item.active) === active),
      );
      if (!pageSize) return HttpResponse.json(page(data));
      const start = Number(query.get("after") ?? 0);
      const end = start + pageSize;
      const hasMore = end < data.length;
      return HttpResponse.json({
        data: data.slice(start, end),
        page: { has_more: hasMore, next_cursor: hasMore ? String(end) : null },
      });
    }),
    http.post(`${CATALOG}/appointments/services`, async ({ request }) => {
      const body = (await request.json()) as Record<string, unknown>;
      state.created.push(body);
      const created = service(`created-${state.created.length}`, String(body.name), {
        duration_minutes: Number(body.duration_minutes),
        price_minor: Number(body.price_minor),
      });
      state.services.push(created);
      return HttpResponse.json({ data: created }, { status: 201 });
    }),
    http.patch(`${CATALOG}/appointments/services/:id`, async ({ request, params }) => {
      const body = (await request.json()) as Partial<Service>;
      state.patched.push({ id: String(params.id), body });
      state.services = state.services.map((item) =>
        item.id === params.id ? { ...item, ...body } : item,
      );
      return HttpResponse.json({ data: state.services.find((item) => item.id === params.id) });
    }),
    http.delete(`${CATALOG}/appointments/services/:id`, ({ params }) => {
      state.archived.push(String(params.id));
      state.services = state.services.map((item) =>
        item.id === params.id ? { ...item, archived_at: "2026-11-17T10:00:00.000Z" } : item,
      );
      return new HttpResponse(null, { status: 204 });
    }),
    http.post(`${CATALOG}/appointments/services/:id/restore`, ({ params }) => {
      state.restored.push(String(params.id));
      state.services = state.services.map((item) =>
        item.id === params.id ? { ...item, archived_at: null } : item,
      );
      return HttpResponse.json({ data: state.services.find((item) => item.id === params.id) });
    }),
    http.get(`${CATALOG}/appointments/branches/:branchId/service_overrides`, () =>
      HttpResponse.json(page(overrides)),
    ),
    http.put(
      `${CATALOG}/appointments/branches/:branchId/services/:serviceId/override`,
      async ({ request, params }) => {
        if (overrideForbidden) {
          return HttpResponse.json(
            {
              type: "urn:ceiba:error:authz.forbidden",
              title: "Prohibido",
              status: 403,
              code: "authz.forbidden",
            },
            { status: 403 },
          );
        }
        const body = (await request.json()) as Record<string, number | null>;
        state.overridePuts.push({ serviceId: String(params.serviceId), body });
        return HttpResponse.json({
          data: serviceOverride("o-new", String(params.serviceId), String(params.branchId), body),
        });
      },
    ),
    http.delete(
      `${CATALOG}/appointments/branches/:branchId/services/:serviceId/override`,
      ({ params }) => {
        state.overrideDeletes.push(String(params.serviceId));
        return new HttpResponse(null, { status: 204 });
      },
    ),
  );
  return state;
}

export { validationProblem };
