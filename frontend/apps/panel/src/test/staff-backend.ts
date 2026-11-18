import type { components } from "@ceiba/api-client";
import { http, HttpResponse } from "msw";
import { CATALOG, page } from "./catalog-backend";
import { validationProblem } from "./fixtures";
import { server } from "./server";

type Professional = components["schemas"]["Professional"];
type Resource = components["schemas"]["Resource"];
type TimeOff = components["schemas"]["TimeOff"];
type Slot = components["schemas"]["WeeklyScheduleSlot"];

const STAFF = `${CATALOG}/appointments`;

// A company manager: manages the whole team and the resources of the company's branches.
export const STAFF_MANAGER_PERMISSIONS = [
  "appointments.service.read",
  "appointments.professional.read",
  "appointments.professional.manage",
  "appointments.professional.assign",
  "appointments.resource.read",
  "appointments.resource.manage",
  "appointments.schedule.read",
  "appointments.schedule.manage",
  "appointments.time_off.read",
  "appointments.time_off.manage",
];

// Reads everything, changes nothing.
export const STAFF_READER_PERMISSIONS = [
  "appointments.service.read",
  "appointments.professional.read",
  "appointments.resource.read",
  "appointments.schedule.read",
  "appointments.time_off.read",
];

const forbidden = () =>
  HttpResponse.json(
    {
      type: "urn:ceiba:error:authz.forbidden",
      title: "Prohibido",
      status: 403,
      code: "authz.forbidden",
    },
    { status: 403 },
  );

interface StaffBackendOptions {
  professionals?: Professional[];
  resources?: Resource[];
  /** Weekly slots by owner id (professional or resource). */
  schedules?: Record<string, Slot[]>;
  /** Absences by owner id, as the branch-scoped lists return them. */
  timeOffs?: Record<string, TimeOff[]>;
  /** Absences of professionals as the company-scope route returns them. */
  companyTimeOffs?: Record<string, TimeOff[]>;
  /** The company-scope absences route answers 403 (the user holds the permission only in a branch). */
  companyTimeOffsForbidden?: boolean;
  /** PUT of a professional schedule answers a 422 on `slots` (overlap with another branch). */
  scheduleOverlap?: boolean;
}

/** In-memory team API (professionals, resources, hours and absences); every write is recorded for assertions. */
export function staffBackend({
  professionals = [],
  resources = [],
  schedules = {},
  timeOffs = {},
  companyTimeOffs = {},
  companyTimeOffsForbidden = false,
  scheduleOverlap = false,
}: StaffBackendOptions = {}) {
  const state = {
    professionals: [...professionals],
    resources: [...resources],
    timeOffs: { ...timeOffs },
    companyTimeOffs: { ...companyTimeOffs },
    createdProfessionals: [] as unknown[],
    patchedProfessionals: [] as { id: string; body: unknown }[],
    archivedProfessionals: [] as string[],
    servicePuts: [] as { id: string; body: unknown }[],
    assignments: [] as { branchId: string; professionalId: string }[],
    unassignments: [] as { branchId: string; professionalId: string }[],
    schedulePuts: [] as { owner: string; body: unknown }[],
    createdTimeOffs: [] as { owner: string; branchId: string; body: Record<string, string> }[],
    deletedTimeOffs: [] as { owner: string; id: string }[],
    deletedCompanyTimeOffs: [] as { owner: string; id: string }[],
    companyTimeOffReads: 0,
    createdResources: [] as { branchId: string; body: unknown }[],
    patchedResources: [] as { id: string; body: unknown }[],
    archivedResources: [] as string[],
  };

  const putSchedule = (kind: "professionals" | "resources") =>
    http.put(
      `${STAFF}/branches/:branchId/${kind}/:ownerId/schedule`,
      async ({ request, params }) => {
        if (scheduleOverlap) {
          return HttpResponse.json(
            validationProblem("slots", "overlap", "Se cruza con el horario en otra sucursal"),
            { status: 422 },
          );
        }
        const body = (await request.json()) as { slots: Omit<Slot, "id">[] };
        state.schedulePuts.push({ owner: String(params.ownerId), body });
        return HttpResponse.json({
          data: body.slots.map((slot, index) => ({ id: `saved-${index}`, ...slot })),
        });
      },
    );

  const timeOffRoutes = (kind: "professionals" | "resources") => [
    http.get(`${STAFF}/branches/:branchId/${kind}/:ownerId/time_offs`, ({ params }) =>
      HttpResponse.json(page(state.timeOffs[String(params.ownerId)] ?? [])),
    ),
    http.post(
      `${STAFF}/branches/:branchId/${kind}/:ownerId/time_offs`,
      async ({ request, params }) => {
        const body = (await request.json()) as Record<string, string>;
        const owner = String(params.ownerId);
        state.createdTimeOffs.push({ owner, branchId: String(params.branchId), body });
        const created: TimeOff = {
          id: `to-${state.createdTimeOffs.length}`,
          professional_id: kind === "professionals" ? owner : null,
          resource_id: kind === "resources" ? owner : null,
          starts_at: body.starts_at!,
          ends_at: body.ends_at!,
          reason: body.reason ?? null,
          created_at: "2026-11-09T12:00:00.000Z",
        };
        state.timeOffs[owner] = [...(state.timeOffs[owner] ?? []), created];
        return HttpResponse.json({ data: created }, { status: 201 });
      },
    ),
    http.delete(`${STAFF}/branches/:branchId/${kind}/:ownerId/time_offs/:id`, ({ params }) => {
      const owner = String(params.ownerId);
      state.deletedTimeOffs.push({ owner, id: String(params.id) });
      state.timeOffs[owner] = (state.timeOffs[owner] ?? []).filter((item) => item.id !== params.id);
      return new HttpResponse(null, { status: 204 });
    }),
  ];

  server.use(
    http.get(`${STAFF}/professionals`, () =>
      HttpResponse.json(page(state.professionals.filter((item) => item.archived_at === null))),
    ),
    http.post(`${STAFF}/professionals`, async ({ request }) => {
      const body = (await request.json()) as { display_name: string; active: boolean };
      state.createdProfessionals.push(body);
      const created: Professional = {
        id: `p-new-${state.createdProfessionals.length}`,
        display_name: body.display_name,
        active: body.active,
        archived_at: null,
        branch_ids: [],
        service_ids: [],
        user_id: null,
        created_at: "2026-11-09T12:00:00.000Z",
        updated_at: "2026-11-09T12:00:00.000Z",
      };
      state.professionals.push(created);
      return HttpResponse.json({ data: created }, { status: 201 });
    }),
    http.patch(`${STAFF}/professionals/:id`, async ({ request, params }) => {
      const body = (await request.json()) as Partial<Professional>;
      state.patchedProfessionals.push({ id: String(params.id), body });
      state.professionals = state.professionals.map((item) =>
        item.id === params.id ? { ...item, ...body } : item,
      );
      return HttpResponse.json({ data: state.professionals.find((item) => item.id === params.id) });
    }),
    http.delete(`${STAFF}/professionals/:id`, ({ params }) => {
      state.archivedProfessionals.push(String(params.id));
      state.professionals = state.professionals.map((item) =>
        item.id === params.id ? { ...item, archived_at: "2026-11-17T10:00:00.000Z" } : item,
      );
      return new HttpResponse(null, { status: 204 });
    }),
    http.put(`${STAFF}/professionals/:id/services`, async ({ request, params }) => {
      const body = (await request.json()) as { service_ids: string[] };
      state.servicePuts.push({ id: String(params.id), body });
      state.professionals = state.professionals.map((item) =>
        item.id === params.id ? { ...item, service_ids: body.service_ids } : item,
      );
      return HttpResponse.json({ data: state.professionals.find((item) => item.id === params.id) });
    }),
    http.put(`${STAFF}/branches/:branchId/professionals/:id/assignment`, ({ params }) => {
      state.assignments.push({
        branchId: String(params.branchId),
        professionalId: String(params.id),
      });
      state.professionals = state.professionals.map((item) =>
        item.id === params.id
          ? { ...item, branch_ids: [...item.branch_ids, String(params.branchId)] }
          : item,
      );
      return HttpResponse.json({ data: state.professionals.find((item) => item.id === params.id) });
    }),
    http.delete(`${STAFF}/branches/:branchId/professionals/:id/assignment`, ({ params }) => {
      state.unassignments.push({
        branchId: String(params.branchId),
        professionalId: String(params.id),
      });
      state.professionals = state.professionals.map((item) =>
        item.id === params.id
          ? { ...item, branch_ids: item.branch_ids.filter((id) => id !== params.branchId) }
          : item,
      );
      return new HttpResponse(null, { status: 204 });
    }),
    http.get(`${STAFF}/branches/:branchId/:kind/:ownerId/schedule`, ({ params }) =>
      HttpResponse.json({ data: schedules[String(params.ownerId)] ?? [] }),
    ),
    putSchedule("professionals"),
    putSchedule("resources"),
    ...timeOffRoutes("professionals"),
    ...timeOffRoutes("resources"),
    http.get(`${STAFF}/professionals/:id/time_offs`, ({ params }) => {
      state.companyTimeOffReads += 1;
      if (companyTimeOffsForbidden) return forbidden();
      return HttpResponse.json(page(state.companyTimeOffs[String(params.id)] ?? []));
    }),
    http.delete(`${STAFF}/professionals/:id/time_offs/:timeOffId`, ({ params }) => {
      const owner = String(params.id);
      state.deletedCompanyTimeOffs.push({ owner, id: String(params.timeOffId) });
      state.companyTimeOffs[owner] = (state.companyTimeOffs[owner] ?? []).filter(
        (item) => item.id !== params.timeOffId,
      );
      return new HttpResponse(null, { status: 204 });
    }),
    http.get(`${STAFF}/branches/:branchId/resources`, ({ params }) =>
      HttpResponse.json(
        page(
          state.resources.filter(
            (item) => item.branch_id === params.branchId && item.archived_at === null,
          ),
        ),
      ),
    ),
    http.post(`${STAFF}/branches/:branchId/resources`, async ({ request, params }) => {
      const body = (await request.json()) as {
        name: string;
        kind: Resource["kind"];
        active: boolean;
      };
      state.createdResources.push({ branchId: String(params.branchId), body });
      const created: Resource = {
        id: `r-new-${state.createdResources.length}`,
        name: body.name,
        kind: body.kind,
        active: body.active,
        archived_at: null,
        branch_id: String(params.branchId),
        created_at: "2026-11-09T12:00:00.000Z",
        updated_at: "2026-11-09T12:00:00.000Z",
      };
      state.resources.push(created);
      return HttpResponse.json({ data: created }, { status: 201 });
    }),
    http.patch(`${STAFF}/branches/:branchId/resources/:id`, async ({ request, params }) => {
      const body = (await request.json()) as Partial<Resource>;
      state.patchedResources.push({ id: String(params.id), body });
      state.resources = state.resources.map((item) =>
        item.id === params.id ? { ...item, ...body } : item,
      );
      return HttpResponse.json({ data: state.resources.find((item) => item.id === params.id) });
    }),
    http.delete(`${STAFF}/branches/:branchId/resources/:id`, ({ params }) => {
      state.archivedResources.push(String(params.id));
      state.resources = state.resources.map((item) =>
        item.id === params.id ? { ...item, archived_at: "2026-11-17T10:00:00.000Z" } : item,
      );
      return new HttpResponse(null, { status: 204 });
    }),
  );
  return state;
}
