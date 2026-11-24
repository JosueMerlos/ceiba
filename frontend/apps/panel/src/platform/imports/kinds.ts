import type { Me } from "../me/me-provider";

export type ImportKind = "customers" | "services" | "professionals";

interface KindDefinition {
  key: ImportKind;
  /** File under /import-templates. */
  template: string;
  /** Module that must be active, if the kind belongs to one. */
  module?: string;
  /** Customers are imported at the branch; catalog kinds at the company (their permission is company-wide). */
  allowed(me: Me): boolean;
}

// Mirrors the backend's import policies: the API checks again on upload.
export const IMPORT_KINDS: readonly KindDefinition[] = [
  {
    key: "customers",
    template: "clientes.csv",
    allowed: (me) =>
      me.permissions.includes("platform.customer.import") &&
      me.permissions.includes("platform.customer.read"),
  },
  {
    key: "services",
    template: "servicios.csv",
    module: "appointments",
    allowed: (me) => me.company_permissions.includes("appointments.service.manage"),
  },
  {
    key: "professionals",
    template: "profesionales.csv",
    module: "appointments",
    allowed: (me) => me.company_permissions.includes("appointments.professional.manage"),
  },
];

export function importKindsFor(me: Me): readonly KindDefinition[] {
  const active = new Set(me.modules.map((module) => module.key));
  return IMPORT_KINDS.filter(
    (kind) => (!kind.module || active.has(kind.module)) && kind.allowed(me),
  );
}
