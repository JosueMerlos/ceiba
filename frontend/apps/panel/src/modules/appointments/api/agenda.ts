import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useQueries, useQuery, type UseQueryResult } from "@tanstack/react-query";
import { useCallback } from "react";
import type { PlainDate } from "../lib/agenda-time";
import { everyServiceQuery } from "./catalog";
import { everyProfessionalQuery, professionalProfileQuery } from "./professionals";
import { everyResourceQuery } from "./resources";
import { APPOINTMENTS_BASE as BASE, useCatalogScope } from "./shared";

type Schemas = components["schemas"];
export type AgendaAppointment = Schemas["AgendaAppointment"];
export type AgendaProfessional = Schemas["Professional"];
export type AgendaResource = Schemas["Resource"];

export const AGENDA_REFRESH_MS = 30_000;

// Every key the agenda owns. Catalog data keeps the keys of its owners, whose mutations invalidate them.
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
  availability: (org: string, company: string) => ["agenda", "availability", org, company] as const,
  slots: (
    org: string,
    company: string,
    branch: string,
    services: string,
    professional: string | null,
    date: string,
  ) => ["agenda", "availability", org, company, branch, services, professional, date] as const,
  details: (org: string, company: string) => ["agenda", "details", org, company] as const,
  detail: (org: string, company: string, branch: string, id: string) =>
    ["agenda", "details", org, company, branch, id] as const,
  chain: (org: string, company: string, branch: string, id: string | null) =>
    ["agenda", "details", org, company, "chain", branch, id] as const,
  customers: (org: string, company: string, branch: string, term: string) =>
    ["agenda", "customers", org, company, branch, term] as const,
};

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

type ServiceRows = { id: string; name: string }[];

function combineServiceNames(results: UseQueryResult<ServiceRows>[]) {
  return new Map(results.flatMap((result) => result.data ?? []).map((row) => [row.id, row.name]));
}

/** Names of every service, archived ones included: an old appointment still shows what was booked. */
export function useAgendaServiceNames() {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQueries({
    queries: [false, true].map((archived) => ({
      ...everyServiceQuery(client, scope, archived),
      throwOnError: false,
    })),
    combine: combineServiceNames,
  });
}

export function useAgendaProfessionals(enabled: boolean) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({ ...everyProfessionalQuery(client, scope), enabled, throwOnError: false });
}

function combineProfiles(results: UseQueryResult<{ id: string; name: string }>[]) {
  return new Map(results.flatMap(({ data }) => (data ? [[data.id, data.name] as const] : [])));
}

/** Display names of professionals the listing does not cover (the user's own profile, someone no longer listed). */
export function useProfessionalProfiles(branchId: string, professionalIds: readonly string[]) {
  const client = useApiClient();
  const scope = useCatalogScope();
  const select = useCallback(
    ({ data }: { data: AgendaProfessional }) => ({ id: data.id, name: data.display_name }),
    [],
  );
  return useQueries({
    queries: professionalIds.map((id) => ({
      ...professionalProfileQuery(client, scope, branchId, id),
      select,
      retry: false,
      throwOnError: false,
    })),
    combine: combineProfiles,
  });
}

export function useAgendaResources(branchId: string, enabled: boolean) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({ ...everyResourceQuery(client, scope, branchId), enabled, throwOnError: false });
}
