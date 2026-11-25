import type { components } from "@ceiba/api-client";
import { delay, http, HttpResponse } from "msw";
import { CATALOG, page } from "./catalog-backend";
import { ids, problem } from "./fixtures";
import { server } from "./server";

type Schemas = components["schemas"];
export type AgendaAppointment = Schemas["AgendaAppointment"];

const BRANCH = (branchId: string) => `${CATALOG}/appointments/branches/${branchId}`;

export const RECEPTION_PERMISSIONS = [
  "appointments.appointment.read",
  "appointments.appointment.create",
  "appointments.appointment.update",
  "appointments.service.read",
  "appointments.professional.read",
  "appointments.resource.read",
  "appointments.schedule.read",
  "appointments.time_off.read",
  "platform.customer.read",
  "platform.customer.create",
];

export const PROFESSIONAL_PERMISSIONS = [
  "appointments.appointment.read_own",
  "appointments.appointment.update_own",
  "appointments.service.read",
  "appointments.professional.read_own",
  "appointments.resource.read",
  "appointments.schedule.read_own",
  "appointments.time_off.manage_own",
];

export const agendaAppointment = (overrides: Partial<AgendaAppointment> = {}): AgendaAppointment =>
  ({
    id: "cita-1",
    branch_id: ids.branchA,
    professional_id: "p1",
    resource_id: null,
    customer_id: "c1",
    customer_name: "Ana Ruiz",
    status: "confirmed",
    source: "panel",
    lock_version: 0,
    rescheduled_from_id: null,
    cancelled_by: null,
    cancellation_reason: null,
    // 09:00 to 09:45 in America/Managua.
    starts_at: "2026-11-18T15:00:00.000Z",
    ends_at: "2026-11-18T15:45:00.000Z",
    services: [
      { service_id: "s1", position: 0, duration_minutes: 45, price_minor: 20_000, currency: "NIO" },
    ],
    total_price_minor: 20_000,
    currency: "NIO",
    ...overrides,
  }) as AgendaAppointment;

const named = (id: string, name: string) => ({ id, name });

interface AgendaBackendOptions {
  appointments?: AgendaAppointment[];
  professionals?: {
    id: string;
    display_name: string;
    branch_ids: string[];
    service_ids: string[];
    /** False for a paused professional; listed as active when left out. */
    active?: boolean;
  }[];
  services?: { id: string; name: string }[];
  archivedServices?: { id: string; name: string }[];
  resources?: { id: string; name: string; active: boolean; archived_at: string | null }[];
  availability?: {
    professional_id: string;
    resource_id: string | null;
    starts_at: string;
    ends_at: string;
  }[];
  customers?: { id: string; full_name: string; phone_e164: string }[];
  /** Forces the answer of the next write: booking, moving or changing a status. */
  writeFailure?: { status: number; code: string };
  /** Someone else saves these notes first: the next save answers 409 and later reads return them. */
  notesSavedByOther?: string;
  /** Holds the answer to a notes save, to observe the form while it is in flight. */
  notesDelayMs?: number;
  /** Details by id; an id left out answers 403, like someone else's appointment for a professional. */
  details?: Record<string, AgendaAppointment & { notes: string | null }>;
  /** Answer 403 to the listing of professionals, like the API does for the `professional` role. */
  professionalsForbidden?: boolean;
  profiles?: Record<string, string>;
  branchId?: string;
  /** Opening hours; left out, the branch and everyone have none, so the whole day is closed. */
  branchSchedule?: WeeklySlot[];
  professionalSchedules?: Record<string, WeeklySlot[]>;
  resourceSchedules?: Record<string, WeeklySlot[]>;
}

type WeeklySlot = { id: string; weekday: number; starts_at_local: string; ends_at_local: string };

export function agendaBackend({
  appointments = [],
  professionals = [
    { id: "p1", display_name: "Rosa Martínez", branch_ids: [ids.branchA], service_ids: ["s1"] },
    { id: "p2", display_name: "Luis Pérez", branch_ids: [ids.branchA], service_ids: ["s1"] },
  ],
  services = [named("s1", "Corte de dama")],
  archivedServices = [],
  resources = [{ id: "r1", name: "Sillón 1", active: true, archived_at: null }],
  availability = [],
  customers = [],
  writeFailure,
  details = {},
  notesSavedByOther,
  notesDelayMs = 0,
  professionalsForbidden = false,
  profiles = {},
  branchId = ids.branchA,
  branchSchedule = [],
  professionalSchedules = {},
  resourceSchedules = {},
}: AgendaBackendOptions = {}) {
  const state = {
    appointmentQueries: [] as URLSearchParams[],
    professionalListCalls: 0,
    availabilityQueries: [] as URLSearchParams[],
    customerQueries: [] as URLSearchParams[],
    writes: [] as { action: string; id: string | null; body: unknown; key: string | null }[],
    createdCustomers: [] as unknown[],
    scheduleOwners: [] as string[],
    detailReads: 0,
    failure: writeFailure,
  };
  const write = async (action: string, id: string | null, request: Request) => {
    const text = await request.text();
    state.writes.push({
      action,
      id,
      body: text ? JSON.parse(text) : null,
      key: request.headers.get("Idempotency-Key"),
    });
    if (state.failure) {
      const { status, code } = state.failure;
      return HttpResponse.json(problem(status, code), { status });
    }
    return HttpResponse.json({ data: agendaAppointment({ id: id ?? "nueva" }) }, { status: 201 });
  };
  let othersNotes: string | null = null;
  const forbidden = () => HttpResponse.json(problem(403, "access.forbidden"), { status: 403 });

  server.use(
    http.get(`${BRANCH(branchId)}/appointments`, ({ request }) => {
      const query = new URL(request.url).searchParams;
      state.appointmentQueries.push(query);
      // Like the API: a professional filter returns only that person's appointments.
      const professionalId = query.get("professional_id");
      return HttpResponse.json({
        data: professionalId
          ? appointments.filter((item) => item.professional_id === professionalId)
          : appointments,
      });
    }),
    http.post(`${BRANCH(branchId)}/appointments`, ({ request }) => write("book", null, request)),
    // Every write moves the version up, as the API does.
    http.get(`${BRANCH(branchId)}/appointments/:id`, ({ params }) => {
      const detail = details[String(params.id)];
      state.detailReads += 1;
      if (!detail) return forbidden();
      return HttpResponse.json({
        data: {
          ...detail,
          notes: othersNotes ?? detail.notes,
          lock_version: detail.lock_version + state.writes.length,
        },
      });
    }),
    http.patch(`${BRANCH(branchId)}/appointments/:id`, async ({ params, request }) => {
      const body = await request.json();
      state.writes.push({ action: "notes", id: String(params.id), body, key: null });
      await delay(notesDelayMs);
      if (notesSavedByOther !== undefined && othersNotes === null) {
        othersNotes = notesSavedByOther;
        return HttpResponse.json(problem(409, "resource.stale"), { status: 409 });
      }
      return HttpResponse.json({ data: details[String(params.id)] });
    }),
    http.post(`${BRANCH(branchId)}/appointments/:id/:action`, ({ params, request }) =>
      write(String(params.action), String(params.id), request),
    ),
    http.get(`${BRANCH(branchId)}/availability`, ({ request }) => {
      state.availabilityQueries.push(new URL(request.url).searchParams);
      return HttpResponse.json({
        data: availability,
        meta: {
          time_zone: "America/Managua",
          duration_minutes: 45,
          buffer_before_minutes: 0,
          buffer_after_minutes: 0,
          price: { amount_minor: 20_000, currency: "NIO" },
          step_minutes: 15,
        },
      });
    }),
    http.get(`${CATALOG}/branches/${branchId}/customers`, ({ request }) => {
      state.customerQueries.push(new URL(request.url).searchParams);
      return HttpResponse.json(page(customers));
    }),
    http.post(`${CATALOG}/branches/${branchId}/customers`, async ({ request }) => {
      const body = (await request.json()) as { full_name: string; phone_e164: string };
      state.createdCustomers.push(body);
      return HttpResponse.json({ data: { id: "c-nuevo", ...body } }, { status: 201 });
    }),
    http.get(`${CATALOG}/appointments/professionals`, () => {
      state.professionalListCalls += 1;
      const listed = professionals.map((person) => ({ active: true, ...person }));
      return professionalsForbidden ? forbidden() : HttpResponse.json(page(listed));
    }),
    http.get(`${BRANCH(branchId)}/professionals/:id`, ({ params }) => {
      const name = profiles[String(params.id)];
      return name
        ? HttpResponse.json({ data: { id: params.id, display_name: name, branch_ids: [branchId] } })
        : forbidden();
    }),
    http.get(`${CATALOG}/appointments/services`, ({ request }) => {
      const archived = new URL(request.url).searchParams.get("archived") === "true";
      return HttpResponse.json(page(archived ? archivedServices : services));
    }),
    http.get(`${BRANCH(branchId)}/resources`, () => HttpResponse.json(page(resources))),
    http.get(`${BRANCH(branchId)}/schedule`, () => HttpResponse.json({ data: branchSchedule })),
    http.get(`${BRANCH(branchId)}/professionals/:id/schedule`, ({ params }) => {
      state.scheduleOwners.push(String(params.id));
      return HttpResponse.json({ data: professionalSchedules[String(params.id)] ?? [] });
    }),
    http.get(`${BRANCH(branchId)}/resources/:id/schedule`, ({ params }) =>
      HttpResponse.json({ data: resourceSchedules[String(params.id)] ?? [] }),
    ),
    http.get(`${BRANCH(branchId)}/professionals/:id/time_offs`, () => HttpResponse.json(page([]))),
    http.get(`${BRANCH(branchId)}/resources/:id/time_offs`, () => HttpResponse.json(page([]))),
  );
  return state;
}
