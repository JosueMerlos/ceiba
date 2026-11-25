import {
  queryKeys,
  unwrap,
  useApiClient,
  useBranchesQuery,
  type components,
} from "@ceiba/api-client";
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  allPages,
  CSRF,
  LIST_PAGE,
  useCatalogScope,
  type CatalogScope,
  type WeeklyScheduleInput,
} from "./shared";

type Schemas = components["schemas"];
export type Service = Schemas["Service"];
export type ServiceInput = Schemas["ServiceInput"];
export type ServicePatch = Schemas["ServicePatch"];
export type ServiceOverride = Schemas["ServiceOverride"];
export type ServiceOverrideInput = Schemas["ServiceOverrideInput"];
export type Branch = Schemas["Branch"];
export type BranchInput = Schemas["BranchInput"];

/** Which services the list shows: paused is "not archived and not active"; archived ignores `active`. */
export type ServiceFilter = "active" | "paused" | "archived";

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

const FILTER_QUERY: Record<ServiceFilter, { archived: boolean; active?: boolean }> = {
  active: { archived: false, active: true },
  paused: { archived: false, active: false },
  archived: { archived: true },
};

/** Every service of one archive state, under the prefix the catalog's mutations invalidate. */
export function everyServiceQuery(
  client: ReturnType<typeof useApiClient>,
  { organizationId, companyId, path }: CatalogScope,
  archived: boolean,
) {
  return {
    queryKey: [...catalogKeys.services(organizationId, companyId), "every-page", archived] as const,
    queryFn: () =>
      allPages((page) =>
        unwrap(
          client.GET(
            "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services",
            { params: { path, query: { ...page, archived } } },
          ),
        ),
      ),
  };
}

/** Every bookable service (all pages, active only): what can be given to a professional. */
export function useEveryActiveServiceQuery() {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({
    ...everyServiceQuery(client, scope, false),
    select: (services: Service[]) => services.filter((service) => service.active),
  });
}

export function useServicesQuery(filter: ServiceFilter) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: catalogKeys.services(organizationId, companyId, filter),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services",
          {
            params: {
              path,
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
  const { path } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (body: ServiceInput) =>
      unwrap(
        client.POST(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services",
          { params: { path, header: CSRF }, body },
        ),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useUpdateService() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: ServicePatch }) =>
      unwrap(
        client.PATCH(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}",
          {
            params: { path: { ...path, id }, header: CSRF },
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
  const { path } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.DELETE(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}",
          { params: { path: { ...path, id }, header: CSRF } },
        ),
      ),
    onSuccess: invalidate,
  });
}

export function useRestoreService() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateServices();
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.POST(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}/restore",
          { params: { path: { ...path, id }, header: CSRF } },
        ),
      ),
    onSuccess: invalidate,
  });
}

export function useServiceOverridesQuery(branchId: string | undefined, { enabled = true } = {}) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: catalogKeys.overrides(organizationId, companyId, branchId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/service_overrides",
          {
            params: {
              path: { ...path, branch_id: branchId! },
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
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: ({ serviceId, body }: { serviceId: string; body: ServiceOverrideInput }) =>
      unwrap(
        client.PUT(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/services/{service_id}/override",
          {
            params: {
              path: {
                ...path,
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
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (serviceId: string) =>
      unwrap(
        client.DELETE(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/services/{service_id}/override",
          {
            params: {
              path: {
                ...path,
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
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    // The caller owns the key: it must survive retries of the same form, which a fresh body object would not.
    mutationFn: ({ body, idempotencyKey }: { body: BranchInput; idempotencyKey: string }) =>
      unwrap(
        client.POST("/api/v1/organizations/{organization_id}/companies/{company_id}/branches", {
          params: { path, header: { ...CSRF, "Idempotency-Key": idempotencyKey } },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: queryKeys.branches(organizationId, companyId) }),
  });
}

export function scheduleQuery(
  client: ReturnType<typeof useApiClient>,
  scope: CatalogScope,
  branchId: string,
) {
  const { organizationId, companyId, path } = scope;
  return {
    queryKey: catalogKeys.schedule(organizationId, companyId, branchId),
    queryFn: () =>
      unwrap(
        client.GET(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/schedule",
          {
            params: {
              path: { ...path, branch_id: branchId },
            },
          },
        ),
      ),
  };
}

export function useBranchScheduleQuery(branchId: string | undefined) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({
    ...scheduleQuery(client, scope, branchId ?? ""),
    enabled: !!branchId,
  });
}

/**
 * Schedules of several branches at once, only to tell "closed" from "has hours" in a list. A failure for one branch
 * (a manager does not read the others) must not take the page down, so these queries never throw to the boundary.
 */
export function useBranchSchedulesQueries(branchIds: readonly string[], { enabled = true } = {}) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQueries({
    queries: branchIds.map((branchId) => ({
      ...scheduleQuery(client, scope, branchId),
      enabled,
      throwOnError: false,
    })),
  });
}

/** Replaces ALL the weekly slots of the branch. A 422 on `slots` (overlap) is shown by the editor. */
export function usePutBranchSchedule(branchId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (body: WeeklyScheduleInput) =>
      unwrap(
        client.PUT(
          "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/schedule",
          {
            params: {
              path: { ...path, branch_id: branchId },
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
