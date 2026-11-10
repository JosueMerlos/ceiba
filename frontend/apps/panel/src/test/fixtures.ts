import type { components } from "@ceiba/api-client";

export type Me = components["schemas"]["Me"]["data"];
type Role = "org_owner" | "company_manager" | "receptionist" | "professional";

export const API = "http://api.test";

export const ids = {
  user: "0198f0a0-0000-7000-8000-0000000000aa",
  orgA: "0198f0a0-0000-7000-8000-000000000a01",
  orgB: "0198f0a0-0000-7000-8000-000000000b01",
  companyA: "0198f0a0-0000-7000-8000-000000000a02",
  companyA2: "0198f0a0-0000-7000-8000-000000000a12",
  companyB: "0198f0a0-0000-7000-8000-000000000b02",
  branchA: "0198f0a0-0000-7000-8000-000000000a03",
  branchA2: "0198f0a0-0000-7000-8000-000000000a13",
  branchB: "0198f0a0-0000-7000-8000-000000000b03",
} as const;

const STAMP = "2026-11-09T12:00:00.000Z";

export const organization = (id: string, name: string) => ({ id, name, status: "active" as const });

export const company = (id: string, name: string) => ({
  id,
  name,
  slug: name.toLowerCase().replace(/\s+/g, "-"),
  business_type: "barbershop",
  currency: "NIO" as const,
  locale: "es-NI",
  status: "active" as const,
  created_at: STAMP,
  updated_at: STAMP,
});

export const branch = (id: string, companyId: string, name: string) => ({
  id,
  company_id: companyId,
  name,
  address: null,
  phone_e164: null,
  time_zone: "America/Managua",
  status: "active" as const,
  created_at: STAMP,
  updated_at: STAMP,
});

// Los permisos de cada rol sobre appointments (manifiesto de backend/packs/modules/appointments/manifest.rb).
const APPOINTMENT_PERMISSIONS: Record<Role, string[]> = {
  org_owner: ["appointments.appointment.count"],
  company_manager: [
    "appointments.appointment.read",
    "appointments.appointment.create",
    "appointments.appointment.update",
    "appointments.appointment.count",
    "appointments.service.read",
  ],
  receptionist: [
    "appointments.appointment.read",
    "appointments.appointment.create",
    "appointments.appointment.update",
    "appointments.service.read",
  ],
  professional: [
    "appointments.appointment.read",
    "appointments.appointment.update_own",
    "appointments.service.read",
  ],
};

interface MeOptions {
  role?: Role;
  /** Módulos activos en la empresa del contexto. */
  modules?: string[];
  organization?: ReturnType<typeof organization>;
  company?: ReturnType<typeof company>;
  branch?: ReturnType<typeof branch> | null;
  name?: string;
}

/** Lo que devolvería GET /api/v1/me: la navegación sale de los permisos y de los módulos activos, como en el backend. */
export function meFixture({
  role = "receptionist",
  modules = ["appointments"],
  organization: org = organization(ids.orgA, "Barbería El Güegüense"),
  company: co = company(ids.companyA, "Barbería El Güegüense"),
  branch: br = branch(ids.branchA, ids.companyA, "Sucursal Centro"),
  name = "Julia Reyes",
}: MeOptions = {}): { data: Me } {
  const active = modules.includes("appointments");
  const permissions = active ? APPOINTMENT_PERMISSIONS[role] : [];
  const navigation = [
    ...(permissions.includes("appointments.appointment.read")
      ? [{ module: "appointments", key: "agenda", path: "/agenda" }]
      : []),
    ...(permissions.includes("appointments.appointment.count")
      ? [{ module: "appointments", key: "summary", path: "/agenda/summary" }]
      : []),
  ];
  return {
    data: {
      principal: { id: ids.user, name, email: "julia@barberia.ceiba.test" },
      context: { organization: org, company: co, branch: br },
      modules: modules.map((key) => ({ key, version: "1.0", settings: {} })),
      permissions,
      navigation,
    },
  };
}

export const authSession = (name = "Julia Reyes") => ({
  data: {
    user: { id: ids.user, email: "julia@barberia.ceiba.test", full_name: name },
    csrf_token: "csrf-de-prueba",
    expires_at: "2026-11-10T12:00:00.000Z",
  },
});

export const problem = (status: number, code: string, title = "Problema") => ({
  type: `urn:ceiba:error:${code}`,
  title,
  status,
  code,
});
