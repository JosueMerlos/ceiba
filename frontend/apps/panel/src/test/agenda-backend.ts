import type { components } from "@ceiba/api-client";
import { http, HttpResponse } from "msw";
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
  professionals?: { id: string; display_name: string; branch_ids: string[] }[];
  services?: { id: string; name: string }[];
  archivedServices?: { id: string; name: string }[];
  resources?: { id: string; name: string; kind?: string; active?: boolean }[];
  /** Answer 403 to the listing of professionals, like the API does for the `professional` role. */
  professionalsForbidden?: boolean;
  profiles?: Record<string, string>;
  branchId?: string;
}

export function agendaBackend({
  appointments = [],
  professionals = [
    { id: "p1", display_name: "Rosa Martínez", branch_ids: [ids.branchA] },
    { id: "p2", display_name: "Luis Pérez", branch_ids: [ids.branchA] },
  ],
  services = [named("s1", "Corte de dama")],
  archivedServices = [],
  resources = [{ id: "r1", name: "Sillón 1" }],
  professionalsForbidden = false,
  profiles = {},
  branchId = ids.branchA,
}: AgendaBackendOptions = {}) {
  const state = { appointmentQueries: [] as URLSearchParams[], professionalListCalls: 0 };
  const forbidden = () =>
    HttpResponse.json(problem(403, "access.forbidden"), { status: 403 });

  server.use(
    http.get(`${BRANCH(branchId)}/appointments`, ({ request }) => {
      state.appointmentQueries.push(new URL(request.url).searchParams);
      return HttpResponse.json({ data: appointments });
    }),
    http.get(`${CATALOG}/appointments/professionals`, () => {
      state.professionalListCalls += 1;
      return professionalsForbidden ? forbidden() : HttpResponse.json(page(professionals));
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
    http.get(`${BRANCH(branchId)}/schedule`, () => HttpResponse.json({ data: [] })),
    http.get(`${BRANCH(branchId)}/professionals/:id/schedule`, () =>
      HttpResponse.json({ data: [] }),
    ),
    http.get(`${BRANCH(branchId)}/resources/:id/schedule`, () => HttpResponse.json({ data: [] })),
    http.get(`${BRANCH(branchId)}/professionals/:id/time_offs`, () =>
      HttpResponse.json(page([])),
    ),
    http.get(`${BRANCH(branchId)}/resources/:id/time_offs`, () => HttpResponse.json(page([]))),
  );
  return state;
}
