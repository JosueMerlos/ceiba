import { unwrap, useApiClient, type ApiClient, type components } from "@ceiba/api-client";
import { useQueries, useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import type { PlainDate } from "../lib/agenda-time";
import { APPOINTMENTS_BASE as BASE, LIST_PAGE, useCatalogScope } from "./shared";

type Schemas = components["schemas"];
export type AgendaAppointment = Schemas["AgendaAppointment"];
export type AgendaProfessional = Schemas["Professional"];
export type AgendaResource = Schemas["Resource"];
type WeeklySlot = Schemas["WeeklyScheduleSlot"];
type TimeOff = Schemas["TimeOff"];

export const AGENDA_REFRESH_MS = 30_000;

export const agendaKeys = {
  all: (org: string, company: string) => ["agenda", "appointments", org, company] as const,
  appointments: (
    org: string,
    company: string,
    branch: string,
    from: string,
    to: string,
    professional?: string,
  ) => ["agenda", "appointments", org, company, branch, from, to, professional ?? "all"] as const,
  catalog: (org: string, company: string, name: string, ...rest: string[]) =>
    ["agenda", "catalog", org, company, name, ...rest] as const,
};

interface Page<T> {
  data: T[];
  page: { has_more: boolean; next_cursor?: string | null };
}

/** The API caps a page at 100: a day's columns and labels must not depend on how long a list happens to be. */
async function allPages<T>(fetchPage: (after?: string) => Promise<Page<T>>) {
  const rows: T[] = [];
  let after: string | undefined;
  for (;;) {
    const { data, page } = await fetchPage(after);
    rows.push(...data);
    if (!page.has_more || !page.next_cursor) return rows;
    after = page.next_cursor;
  }
}

export function useAgendaAppointments(
  branchId: string,
  from: PlainDate,
  to: PlainDate,
  { professionalId, enabled = true }: { professionalId?: string; enabled?: boolean } = {},
) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.appointments(
      organizationId,
      companyId,
      branchId,
      from,
      to,
      professionalId,
    ),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/appointments`, {
          params: {
            path: { ...path, branch_id: branchId },
            query: { from, to, ...(professionalId ? { professional_id: professionalId } : {}) },
          },
        }),
      ),
    enabled,
    refetchInterval: AGENDA_REFRESH_MS,
    // "always": the screen stays open all day, and the data may be fresher than staleTime yet already outdated.
    refetchOnWindowFocus: "always",
  });
}

/** Names of every service, archived ones included: an old appointment still shows what was booked. */
export function useAgendaServiceNames() {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  const results = useQueries({
    queries: [false, true].map((archived) => ({
      queryKey: agendaKeys.catalog(organizationId, companyId, "services", String(archived)),
      queryFn: () =>
        allPages((after) =>
          unwrap(
            client.GET(`${BASE}/services`, {
              params: { path, query: { ...LIST_PAGE, archived, ...(after ? { after } : {}) } },
            }),
          ),
        ),
      throwOnError: false,
    })),
  });
  const [active, archived] = [results[0]?.data, results[1]?.data];
  return useMemo(
    () => new Map([...(active ?? []), ...(archived ?? [])].map((item) => [item.id, item.name])),
    [active, archived],
  );
}

export function useAgendaProfessionals(enabled: boolean) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.catalog(organizationId, companyId, "professionals"),
    queryFn: () =>
      allPages((after) =>
        unwrap(
          client.GET(`${BASE}/professionals`, {
            params: { path, query: { ...LIST_PAGE, ...(after ? { after } : {}) } },
          }),
        ),
      ),
    enabled,
    throwOnError: false,
  });
}

/** Display names of professionals the listing does not cover (the user's own profile, someone no longer listed). */
export function useProfessionalProfiles(branchId: string, professionalIds: readonly string[]) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  const results = useQueries({
    queries: professionalIds.map((id) => ({
      queryKey: agendaKeys.catalog(organizationId, companyId, "profile", branchId, id),
      queryFn: () =>
        unwrap(
          client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}`, {
            params: { path: { ...path, branch_id: branchId, professional_id: id } },
          }),
        ),
      retry: false,
      throwOnError: false,
    })),
  });
  const names = results.map((result) => result.data?.data.display_name ?? "").join("\u0000");
  const idsKey = professionalIds.join();
  return useMemo(() => {
    const split = names.split("\u0000");
    return Object.fromEntries(
      professionalIds.flatMap((id, index) => (split[index] ? [[id, split[index]]] : [])),
    ) as Record<string, string>;
    // `names` stands for the query results, which are a new array on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [names, idsKey]);
}

export function useAgendaResources(branchId: string, enabled: boolean) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.catalog(organizationId, companyId, "resources", branchId),
    queryFn: () =>
      allPages((after) =>
        unwrap(
          client.GET(`${BASE}/branches/{branch_id}/resources`, {
            params: {
              path: { ...path, branch_id: branchId },
              query: { ...LIST_PAGE, ...(after ? { after } : {}) },
            },
          }),
        ),
      ),
    enabled,
    throwOnError: false,
  });
}

export function useAgendaBranchSchedule(branchId: string, enabled: boolean) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.catalog(organizationId, companyId, "branch-schedule", branchId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/schedule`, {
          params: { path: { ...path, branch_id: branchId } },
        }),
      ),
    enabled,
    throwOnError: false,
  });
}

export interface OwnerAvailability {
  slots: readonly WeeklySlot[];
  timeOffs: readonly TimeOff[];
}

type OwnerKind = "professional" | "resource";

function ownerRequests(
  client: ApiClient,
  path: { organization_id: string; company_id: string },
  branchId: string,
  kind: OwnerKind,
  id: string,
) {
  const branchPath = { ...path, branch_id: branchId };
  if (kind === "professional") {
    const params = { path: { ...branchPath, professional_id: id } };
    return {
      schedule: () =>
        unwrap(
          client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}/schedule`, {
            params,
          }),
        ),
      timeOffs: (after?: string) =>
        unwrap(
          client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}/time_offs`, {
            params: { ...params, query: { ...LIST_PAGE, ...(after ? { after } : {}) } },
          }),
        ),
    };
  }
  const params = { path: { ...branchPath, resource_id: id } };
  return {
    schedule: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/resources/{resource_id}/schedule`, { params }),
      ),
    timeOffs: (after?: string) =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/resources/{resource_id}/time_offs`, {
          params: { ...params, query: { ...LIST_PAGE, ...(after ? { after } : {}) } },
        }),
      ),
  };
}

/**
 * Hours and absences per column. A failure only costs the shading of that column, so it never takes the screen down, and
 * an owner still loading or failed is simply missing from the result: unknown is not the same as closed.
 */
export function useOwnerAvailability(
  branchId: string,
  kind: OwnerKind,
  ownerIds: readonly string[],
  enabled: boolean,
) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  const results = useQueries({
    queries: ownerIds.map((id) => ({
      queryKey: agendaKeys.catalog(organizationId, companyId, `${kind}-availability`, branchId, id),
      queryFn: async (): Promise<OwnerAvailability> => {
        const requests = ownerRequests(client, path, branchId, kind, id);
        const [schedule, timeOffs] = await Promise.all([
          requests.schedule(),
          allPages(requests.timeOffs),
        ]);
        return { slots: schedule.data, timeOffs };
      },
      enabled,
      retry: false,
      throwOnError: false,
    })),
  });
  const stamp = results.map((result) => result.dataUpdatedAt).join();
  const idsKey = ownerIds.join();
  return useMemo(() => {
    const entries = ownerIds.flatMap((id, index) => {
      const data = results[index]?.data;
      return data ? [[id, data] as const] : [];
    });
    return new Map<string, OwnerAvailability>(entries);
    // `stamp` stands for the query results, which are a new array on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stamp, idsKey]);
}
