import type { components } from "@ceiba/api-client";
import { useMe } from "../../../platform/me/me-provider";

type Schemas = components["schemas"];
export type WeeklyScheduleSlot = Schemas["WeeklyScheduleSlot"];
export type WeeklyScheduleInput = Schemas["WeeklyScheduleInput"];
export type TimeOff = Schemas["TimeOff"];
export type TimeOffInput = Schemas["TimeOffInput"];

// The contract declares X-CSRF-Token as required; the client middleware replaces this with the real token.
export const CSRF = { "X-CSRF-Token": "" };
export const LIST_PAGE = { limit: 100 };
export const APPOINTMENTS_BASE =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments";

interface Page<T> {
  data: T[];
  page: { has_more: boolean; next_cursor?: string | null };
}

/** Walks every page of a list: the API caps a page at 100 and a screen may need the whole list. */
export async function allPages<T>(
  fetchPage: (query: { limit: number; after?: string }) => Promise<Page<T>>,
) {
  const rows: T[] = [];
  let after: string | undefined;
  for (;;) {
    const { data, page } = await fetchPage({ ...LIST_PAGE, ...(after ? { after } : {}) });
    rows.push(...data);
    if (!page.has_more || !page.next_cursor) return rows;
    after = page.next_cursor;
  }
}

/** Organization and company the catalog belongs to: always the working context from /me, never from the URL. */
export type CatalogScope = ReturnType<typeof useCatalogScope>;

export function useCatalogScope() {
  const { context } = useMe();
  if (!context.organization || !context.company) {
    throw new Error("El catálogo necesita una organización y una empresa en el contexto");
  }
  const organizationId = context.organization.id;
  const companyId = context.company.id;
  return {
    organizationId,
    companyId,
    currency: context.company.currency,
    path: { organization_id: organizationId, company_id: companyId },
  };
}
