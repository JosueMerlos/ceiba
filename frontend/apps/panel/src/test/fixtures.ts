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

// Each role's permissions on appointments (backend/packs/modules/appointments/manifest.rb manifest).
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
    "appointments.appointment.read_own",
    "appointments.appointment.update_own",
    "appointments.service.read",
  ],
};

interface MeOptions {
  role?: Role;
  /** Replaces the role's permission list (catalog screens need role mixes the base table does not model). */
  permissions?: string[];
  /** Keys held at COMPANY scope; by default a company manager holds all of them and anyone else none (branch roles only hold them in their branch). */
  companyPermissions?: string[];
  modules?: string[];
  organization?: ReturnType<typeof organization>;
  company?: ReturnType<typeof company>;
  branch?: ReturnType<typeof branch> | null;
  name?: string;
  /** Platform permissions on top of the role's (e.g. "platform.branding.update"). */
  extraPermissions?: string[];
}

/** What GET /api/v1/me would return: navigation derives from permissions and active modules, as in the backend. */
export function meFixture({
  role = "receptionist",
  permissions: explicitPermissions,
  companyPermissions: explicitCompanyPermissions,
  modules = ["appointments"],
  organization: org = organization(ids.orgA, "Barbería El Güegüense"),
  company: co = company(ids.companyA, "Barbería El Güegüense"),
  branch: br = branch(ids.branchA, ids.companyA, "Sucursal Centro"),
  name = "Julia Reyes",
  extraPermissions = [],
}: MeOptions = {}): { data: Me } {
  const active = modules.includes("appointments");
  const permissions = [
    ...(active ? (explicitPermissions ?? APPOINTMENT_PERMISSIONS[role]) : []),
    ...extraPermissions,
  ];
  // Models only company-scope grants: the upward read keys that branch roles get (from_descendants) are left out.
  const companyPermissions = active
    ? (explicitCompanyPermissions ?? (role === "company_manager" ? permissions : []))
    : [];
  const navigation = [
    ...(permissions.includes("platform.customer.read")
      ? [{ module: "platform", key: "customers", path: "/customers" }]
      : []),
    ...(permissions.includes("appointments.appointment.read") ||
    permissions.includes("appointments.appointment.read_own")
      ? [{ module: "appointments", key: "agenda", path: "/agenda" }]
      : []),
    ...(permissions.includes("appointments.appointment.count")
      ? [{ module: "appointments", key: "summary", path: "/agenda/summary" }]
      : []),
    ...(permissions.includes("appointments.service.read")
      ? [{ module: "appointments", key: "services", path: "/services" }]
      : []),
    ...(permissions.includes("appointments.professional.read")
      ? [{ module: "appointments", key: "professionals", path: "/professionals" }]
      : []),
    ...(permissions.includes("appointments.resource.read")
      ? [{ module: "appointments", key: "resources", path: "/resources" }]
      : []),
    ...(permissions.includes("appointments.schedule.read")
      ? [{ module: "appointments", key: "branches", path: "/branches" }]
      : []),
  ];
  return {
    data: {
      principal: { id: ids.user, name, email: "julia@barberia.ceiba.test" },
      context: { organization: org, company: co, branch: br },
      modules: modules.map((key) => ({ key, version: "1.0", settings: {} })),
      permissions,
      company_permissions: companyPermissions,
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

type Branding = components["schemas"]["Branding"];

/** What the branding endpoints return for a company with no customization (everything null). */
export const brandingFixture = (overrides: Partial<Branding> = {}): { data: Branding } => ({
  data: {
    brand_name: null,
    tagline: null,
    primary_color: null,
    secondary_color: null,
    accent_color: null,
    font_choice: null,
    assets: { logo: null, banner: null, favicon: null },
    ...overrides,
  },
});

export const service = (
  id: string,
  name: string,
  overrides: Partial<components["schemas"]["Service"]> = {},
): components["schemas"]["Service"] => ({
  id,
  name,
  active: true,
  archived_at: null,
  buffer_after_minutes: 0,
  buffer_before_minutes: 0,
  currency: "NIO",
  duration_minutes: 30,
  position: 0,
  price_minor: 20000,
  created_at: STAMP,
  updated_at: STAMP,
  ...overrides,
});

export const serviceOverride = (
  id: string,
  serviceId: string,
  branchId: string,
  overrides: Partial<components["schemas"]["ServiceOverride"]> = {},
): components["schemas"]["ServiceOverride"] => ({
  id,
  service_id: serviceId,
  branch_id: branchId,
  currency: "NIO",
  duration_minutes: null,
  price_minor: null,
  created_at: STAMP,
  updated_at: STAMP,
  ...overrides,
});

export const scheduleSlot = (
  id: string,
  weekday: number,
  starts: string,
  ends: string,
): components["schemas"]["WeeklyScheduleSlot"] => ({
  id,
  weekday,
  starts_at_local: starts,
  ends_at_local: ends,
});

export const validationProblem = (field: string, code: string, message: string) => ({
  ...problem(422, "validation.failed", "Datos inválidos"),
  errors: [{ field, code, message }],
});

export const professional = (
  id: string,
  displayName: string,
  overrides: Partial<components["schemas"]["Professional"]> = {},
): components["schemas"]["Professional"] => ({
  id,
  display_name: displayName,
  active: true,
  archived_at: null,
  branch_ids: [],
  service_ids: [],
  user_id: null,
  created_at: STAMP,
  updated_at: STAMP,
  ...overrides,
});

export const resource = (
  id: string,
  name: string,
  overrides: Partial<components["schemas"]["Resource"]> = {},
): components["schemas"]["Resource"] => ({
  id,
  name,
  kind: "chair",
  active: true,
  archived_at: null,
  branch_id: ids.branchA,
  created_at: STAMP,
  updated_at: STAMP,
  ...overrides,
});

export const timeOff = (
  id: string,
  owner: { professionalId?: string; resourceId?: string },
  startsAt: string,
  endsAt: string,
  reason: string | null = null,
): components["schemas"]["TimeOff"] => ({
  id,
  professional_id: owner.professionalId ?? null,
  resource_id: owner.resourceId ?? null,
  starts_at: startsAt,
  ends_at: endsAt,
  reason,
  created_at: STAMP,
});
