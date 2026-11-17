import {
  queryKeys,
  unwrap,
  useApiClient,
  useBranchesQuery,
  type components,
} from "@ceiba/api-client";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMe } from "../../../platform/me/me-provider";

type Schemas = components["schemas"];
export type Service = Schemas["Service"];
export type ServiceInput = Schemas["ServiceInput"];
export type ServicePatch = Schemas["ServicePatch"];
export type ServiceOverride = Schemas["ServiceOverride"];
export type ServiceOverrideInput = Schemas["ServiceOverrideInput"];
export type Branch = Schemas["Branch"];
export type BranchInput = Schemas["BranchInput"];
export type WeeklyScheduleSlot = Schemas["WeeklyScheduleSlot"];
export type WeeklyScheduleInput = Schemas["WeeklyScheduleInput"];

/** Which services the list shows: paused is "not archived and not active"; archived ignores `active`. */
export type ServiceFilter = "active" | "paused" | "archived";

// The contract declares X-CSRF-Token as required; the client middleware replaces this with the real token.
const CSRF = { "X-CSRF-Token": "" };

// Every key carries organization and company (and branch where it applies): a context switch also drops the cache, but
// the key alone must never let two companies share an entry.
export const catalogKeys = {
  services: (org: string, company: string, filter?: ServiceFilter) =>
    ["catalog", "services", org, company, ...(filter ? [filter] : [])] as const,
  overrides: (org: string, company: string, branch: string) =>
    ["catalog", "service-overrides", org, company, branch] as const,
  schedule: (org: string, company: string, branch: string) =>
    ["catalog", "branch-schedule", org, company, branch] as const,
};

const LIST_PAGE = { limit: 100 };

/** Organization and company the catalog belongs to: always the working context from /me, never from the URL. */
export function useCatalogScope() {
  const { context } = useMe();
  if (!context.organization || !context.company) {
    throw new Error("El catálogo necesita una organización y una empresa en el contexto");
  }
  return {
    organizationId: context.organization.id,
    companyId: context.company.id,
    currency: context.company.currency,
  };
}

function servicesPath(organizationId: string, companyId: string) {
  return { organization_id: organizationId, company_id: companyId };
}

const FILTER_QUERY: Record<ServiceFilter, { archived: boolean; active?: boolean }> = {
  active: { archived: false, active: true },
  paused: { archived: false, active: false },
  archived: { archived: true },
};

export function useServicesQuery(filter: ServiceFilter) {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  return useQuery({
    queryKey: catalogKeys.services(organizationId, companyId, filter),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services",
          {
            params: {
              path: servicesPath(organizationId, companyId),
              query: { ...FILTER_QUERY[filter], ...LIST_PAGE },
            },
          },
        ),
      ),
  });
}

function useInvalidateServices() {
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return () =>
    queryClient.invalidateQueries({ queryKey: catalogKeys.services(organizationId, companyId) });
}

// Form mutations are `silent`: the form shows the failure next to the fields, so the global toast would repeat it.
export function useCreateService() {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (body: ServiceInput) =>
      unwrap(
        client.POST(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services",
          { params: { path: servicesPath(organizationId, companyId), header: CSRF }, body },
        ),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useUpdateService() {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: ServicePatch }) =>
      unwrap(
        client.PATCH(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}",
          {
            params: { path: { ...servicesPath(organizationId, companyId), id }, header: CSRF },
            body,
          },
        ),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useArchiveService() {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.DELETE(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}",
          { params: { path: { ...servicesPath(organizationId, companyId), id }, header: CSRF } },
        ),
      ),
    onSuccess: invalidate,
  });
}

export function useRestoreService() {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.POST(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}/restore",
          { params: { path: { ...servicesPath(organizationId, companyId), id }, header: CSRF } },
        ),
      ),
    onSuccess: invalidate,
  });
}

export function useServiceOverridesQuery(branchId: string | undefined, { enabled = true } = {}) {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  return useQuery({
    queryKey: catalogKeys.overrides(organizationId, companyId, branchId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/service_overrides",
          {
            params: {
              path: { ...servicesPath(organizationId, companyId), branch_id: branchId! },
              query: LIST_PAGE,
            },
          },
        ),
      ),
    enabled: enabled && !!branchId,
  });
}

/** PUT is a merge: send only the keys the user changed (null removes a value). */
export function usePutServiceOverride(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return useMutation({
    mutationFn: ({ serviceId, body }: { serviceId: string; body: ServiceOverrideInput }) =>
      unwrap(
        client.PUT(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/services/{service_id}/override",
          {
            params: {
              path: {
                ...servicesPath(organizationId, companyId),
                branch_id: branchId,
                service_id: serviceId,
              },
              header: CSRF,
            },
            body,
          },
        ),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: catalogKeys.overrides(organizationId, companyId, branchId),
      }),
  });
}

export function useDeleteServiceOverride(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return useMutation({
    mutationFn: (serviceId: string) =>
      unwrap(
        client.DELETE(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/services/{service_id}/override",
          {
            params: {
              path: {
                ...servicesPath(organizationId, companyId),
                branch_id: branchId,
                service_id: serviceId,
              },
              header: CSRF,
            },
          },
        ),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: catalogKeys.overrides(organizationId, companyId, branchId),
      }),
  });
}

/** Branches of the working company (the same cache the context selector uses). */
export function useCompanyBranchesQuery() {
  const { organizationId, companyId } = useCatalogScope();
  return useBranchesQuery(organizationId, companyId);
}

export function useCreateBranch() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return useMutation({
    mutationFn: (body: BranchInput) =>
      unwrap(
        client.POST("/api/v1/organizations/{organization_id}/companies/{company_id}/branches", {
          params: {
            path: { organization_id: organizationId, company_id: companyId },
            header: CSRF,
          },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: queryKeys.branches(organizationId, companyId) }),
  });
}

function scheduleQuery(
  client: ReturnType<typeof useApiClient>,
  organizationId: string,
  companyId: string,
  branchId: string,
) {
  return {
    queryKey: catalogKeys.schedule(organizationId, companyId, branchId),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/schedule",
          {
            params: {
              path: { ...servicesPath(organizationId, companyId), branch_id: branchId },
            },
          },
        ),
      ),
  };
}

export function useBranchScheduleQuery(branchId: string | undefined) {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  return useQuery({
    ...scheduleQuery(client, organizationId, companyId, branchId ?? ""),
    enabled: !!branchId,
  });
}

/**
 * Schedules of several branches at once, only to tell "closed" from "has hours" in a list. A failure for one branch
 * (a manager does not read the others) must not take the page down, so these queries never throw to the boundary.
 */
export function useBranchSchedulesQueries(branchIds: readonly string[], { enabled = true } = {}) {
  const client = useApiClient();
  const { organizationId, companyId } = useCatalogScope();
  return useQueries({
    queries: branchIds.map((branchId) => ({
      ...scheduleQuery(client, organizationId, companyId, branchId),
      enabled,
      throwOnError: false,
    })),
  });
}

/** Replaces ALL the weekly slots of the branch. A 422 on `slots` (overlap) is shown by the editor. */
export function usePutBranchSchedule(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return useMutation({
    mutationFn: (body: WeeklyScheduleInput) =>
      unwrap(
        client.PUT(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/schedule",
          {
            params: {
              path: { ...servicesPath(organizationId, companyId), branch_id: branchId },
              header: CSRF,
            },
            body,
          },
        ),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: catalogKeys.schedule(organizationId, companyId, branchId),
      }),
  });
}
