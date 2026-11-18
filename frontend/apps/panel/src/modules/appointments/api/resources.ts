import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useCatalogScope } from "./catalog";
import type { TimeOffInput, WeeklyScheduleInput } from "./professionals";

type Schemas = components["schemas"];
export type Resource = Schemas["Resource"];
export type ResourceInput = Schemas["ResourceInput"];
export type ResourcePatch = Schemas["ResourcePatch"];
export type ResourceKind = Resource["kind"];

/** The contract's own enum, in the order the form offers it. */
export const RESOURCE_KINDS: readonly ResourceKind[] = ["chair", "room", "equipment"];

const CSRF = { "X-CSRF-Token": "" };
const LIST_PAGE = { limit: 100 };
const BASE = "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments";

export const resourceKeys = {
  all: (org: string, company: string, branch: string) =>
    ["catalog", "resources", org, company, branch] as const,
  schedule: (org: string, company: string, branch: string, resource: string) =>
    ["catalog", "resource-schedule", org, company, branch, resource] as const,
  timeOffs: (org: string, company: string, branch: string, resource: string) =>
    ["catalog", "resource-time-offs", org, company, branch, resource] as const,
};

function useScope() {
  const { organizationId, companyId } = useCatalogScope();
  return {
    organizationId,
    companyId,
    path: { organization_id: organizationId, company_id: companyId },
  };
}

export function useResourcesQuery(branchId: string | undefined) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useScope();
  return useQuery({
    queryKey: resourceKeys.all(organizationId, companyId, branchId ?? ""),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/resources`, {
          params: { path: { ...path, branch_id: branchId! }, query: LIST_PAGE },
        }),
      ),
    enabled: !!branchId,
  });
}

function useInvalidateResources(branchId: string) {
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useScope();
  return () =>
    queryClient.invalidateQueries({
      queryKey: resourceKeys.all(organizationId, companyId, branchId),
    });
}

export function useCreateResource(branchId: string) {
  const client = useApiClient();
  const { path } = useScope();
  const invalidate = useInvalidateResources(branchId);
  return useMutation({
    mutationFn: (body: ResourceInput) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/resources`, {
          params: { path: { ...path, branch_id: branchId }, header: CSRF },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useUpdateResource(branchId: string) {
  const client = useApiClient();
  const { path } = useScope();
  const invalidate = useInvalidateResources(branchId);
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: ResourcePatch }) =>
      unwrap(
        client.PATCH(`${BASE}/branches/{branch_id}/resources/{resource_id}`, {
          params: { path: { ...path, branch_id: branchId, resource_id: id }, header: CSRF },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useArchiveResource(branchId: string) {
  const client = useApiClient();
  const { path } = useScope();
  const invalidate = useInvalidateResources(branchId);
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.DELETE(`${BASE}/branches/{branch_id}/resources/{resource_id}`, {
          params: { path: { ...path, branch_id: branchId, resource_id: id }, header: CSRF },
        }),
      ),
    onSuccess: invalidate,
  });
}

export function useResourceScheduleQuery(
  branchId: string,
  resourceId: string,
  { enabled = true } = {},
) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useScope();
  return useQuery({
    queryKey: resourceKeys.schedule(organizationId, companyId, branchId, resourceId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/resources/{resource_id}/schedule`, {
          params: { path: { ...path, branch_id: branchId, resource_id: resourceId } },
        }),
      ),
    enabled,
    throwOnError: false,
  });
}

/** Replaces ALL the weekly slots of the resource. */
export function usePutResourceSchedule(branchId: string, resourceId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useScope();
  return useMutation({
    mutationFn: (body: WeeklyScheduleInput) =>
      unwrap(
        client.PUT(`${BASE}/branches/{branch_id}/resources/{resource_id}/schedule`, {
          params: {
            path: { ...path, branch_id: branchId, resource_id: resourceId },
            header: CSRF,
          },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: resourceKeys.schedule(organizationId, companyId, branchId, resourceId),
      }),
  });
}

export function useResourceTimeOffsQuery(
  branchId: string,
  resourceId: string,
  { enabled = true } = {},
) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useScope();
  return useQuery({
    queryKey: resourceKeys.timeOffs(organizationId, companyId, branchId, resourceId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/resources/{resource_id}/time_offs`, {
          params: { path: { ...path, branch_id: branchId, resource_id: resourceId } },
        }),
      ),
    enabled,
    throwOnError: false,
  });
}

export function useCreateResourceTimeOff(branchId: string, resourceId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useScope();
  return useMutation({
    mutationFn: (body: TimeOffInput) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/resources/{resource_id}/time_offs`, {
          params: {
            path: { ...path, branch_id: branchId, resource_id: resourceId },
            header: CSRF,
          },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: resourceKeys.timeOffs(organizationId, companyId, branchId, resourceId),
      }),
  });
}

export function useDeleteResourceTimeOff(branchId: string, resourceId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useScope();
  return useMutation({
    mutationFn: (timeOffId: string) =>
      unwrap(
        client.DELETE(
          `${BASE}/branches/{branch_id}/resources/{resource_id}/time_offs/{resource_time_off_id}`,
          {
            params: {
              path: {
                ...path,
                branch_id: branchId,
                resource_id: resourceId,
                resource_time_off_id: timeOffId,
              },
              header: CSRF,
            },
          },
        ),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: resourceKeys.timeOffs(organizationId, companyId, branchId, resourceId),
      }),
  });
}
