import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  allPages,
  APPOINTMENTS_BASE as BASE,
  CSRF,
  LIST_PAGE,
  useCatalogScope,
  type CatalogScope,
  type TimeOffInput,
  type WeeklyScheduleInput,
} from "./shared";

type Schemas = components["schemas"];
export type Professional = Schemas["Professional"];
export type ProfessionalInput = Schemas["ProfessionalInput"];
export type ProfessionalPatch = Schemas["ProfessionalPatch"];

// Every key carries organization and company (and branch where it applies) so two companies never share an entry.
export const professionalKeys = {
  all: (org: string, company: string) => ["catalog", "professionals", org, company] as const,
  schedule: (org: string, company: string, branch: string, professional: string) =>
    ["catalog", "professional-schedule", org, company, branch, professional] as const,
  timeOffs: (org: string, company: string, branch: string, professional: string) =>
    ["catalog", "professional-time-offs", org, company, branch, professional] as const,
  companyTimeOffs: (org: string, company: string, professional: string) =>
    ["catalog", "professional-company-time-offs", org, company, professional] as const,
};

type Client = ReturnType<typeof useApiClient>;

// The agenda's queries live under the prefixes the mutations below invalidate, so an edit here reaches it.
export function everyProfessionalQuery(
  client: Client,
  { organizationId, companyId, path }: CatalogScope,
) {
  return {
    queryKey: [...professionalKeys.all(organizationId, companyId), "every-page"] as const,
    queryFn: () =>
      allPages((query) => unwrap(client.GET(`${BASE}/professionals`, { params: { path, query } }))),
  };
}

export function professionalProfileQuery(
  client: Client,
  { organizationId, companyId, path }: CatalogScope,
  branchId: string,
  professionalId: string,
) {
  return {
    queryKey: [
      ...professionalKeys.all(organizationId, companyId),
      "profile",
      branchId,
      professionalId,
    ] as const,
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}`, {
          params: { path: { ...path, branch_id: branchId, professional_id: professionalId } },
        }),
      ),
  };
}

export function professionalScheduleQuery(
  client: Client,
  { organizationId, companyId, path }: CatalogScope,
  branchId: string,
  professionalId: string,
) {
  return {
    queryKey: professionalKeys.schedule(organizationId, companyId, branchId, professionalId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}/schedule`, {
          params: { path: { ...path, branch_id: branchId, professional_id: professionalId } },
        }),
      ),
  };
}

export function everyProfessionalTimeOffQuery(
  client: Client,
  { organizationId, companyId, path }: CatalogScope,
  branchId: string,
  professionalId: string,
) {
  return {
    queryKey: [
      ...professionalKeys.timeOffs(organizationId, companyId, branchId, professionalId),
      "every-page",
    ] as const,
    queryFn: () =>
      allPages((query) =>
        unwrap(
          client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}/time_offs`, {
            params: {
              path: { ...path, branch_id: branchId, professional_id: professionalId },
              query,
            },
          }),
        ),
      ),
  };
}

export function useProfessionalsQuery() {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: professionalKeys.all(organizationId, companyId),
    queryFn: () =>
      unwrap(client.GET(`${BASE}/professionals`, { params: { path, query: LIST_PAGE } })),
  });
}

function useInvalidateProfessionals() {
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return () =>
    queryClient.invalidateQueries({ queryKey: professionalKeys.all(organizationId, companyId) });
}

// Form mutations are `silent`: the form shows the failure next to the fields, so the global toast would repeat it.
export function useCreateProfessional() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateProfessionals();
  return useMutation({
    mutationFn: (body: ProfessionalInput) =>
      unwrap(client.POST(`${BASE}/professionals`, { params: { path, header: CSRF }, body })),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useUpdateProfessional() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateProfessionals();
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: ProfessionalPatch }) =>
      unwrap(
        client.PATCH(`${BASE}/professionals/{professional_id}`, {
          params: { path: { ...path, professional_id: id }, header: CSRF },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

export function useArchiveProfessional() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateProfessionals();
  return useMutation({
    mutationFn: (id: string) =>
      unwrap(
        client.DELETE(`${BASE}/professionals/{professional_id}`, {
          params: { path: { ...path, professional_id: id }, header: CSRF },
        }),
      ),
    onSuccess: invalidate,
  });
}

/** PUT replaces the WHOLE set of services the professional provides. */
export function usePutProfessionalServices() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateProfessionals();
  return useMutation({
    mutationFn: ({ id, serviceIds }: { id: string; serviceIds: string[] }) =>
      unwrap(
        client.PUT(`${BASE}/professionals/{professional_id}/services`, {
          params: { path: { ...path, professional_id: id }, header: CSRF },
          body: { service_ids: serviceIds },
        }),
      ),
    meta: { silent: true },
    onSuccess: invalidate,
  });
}

/** Assigns (`assign`) or removes (`unassign`) a professional in a branch; both refresh the list of professionals. */
export function useProfessionalAssignment() {
  const client = useApiClient();
  const { path } = useCatalogScope();
  const invalidate = useInvalidateProfessionals();
  return useMutation({
    mutationFn: ({
      branchId,
      professionalId,
      assign,
    }: {
      branchId: string;
      professionalId: string;
      assign: boolean;
    }) => {
      const params = {
        path: { ...path, branch_id: branchId, professional_id: professionalId },
        header: CSRF,
      };
      const url =
        `${BASE}/branches/{branch_id}/professionals/{professional_id}/assignment` as const;
      if (assign) return unwrap(client.PUT(url, { params }));
      return unwrap(client.DELETE(url, { params }));
    },
    onSuccess: invalidate,
  });
}

export function useProfessionalScheduleQuery(
  branchId: string,
  professionalId: string,
  { enabled = true } = {},
) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({
    ...professionalScheduleQuery(client, scope, branchId, professionalId),
    enabled,
    throwOnError: false,
  });
}

/** Replaces ALL the weekly slots of the professional in this branch; a 422 on `slots` is shown by the editor. */
export function usePutProfessionalSchedule(branchId: string, professionalId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (body: WeeklyScheduleInput) =>
      unwrap(
        client.PUT(`${BASE}/branches/{branch_id}/professionals/{professional_id}/schedule`, {
          params: {
            path: { ...path, branch_id: branchId, professional_id: professionalId },
            header: CSRF,
          },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: professionalKeys.schedule(organizationId, companyId, branchId, professionalId),
      }),
  });
}

export function useProfessionalTimeOffsQuery(
  branchId: string,
  professionalId: string,
  { enabled = true } = {},
) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: professionalKeys.timeOffs(organizationId, companyId, branchId, professionalId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/professionals/{professional_id}/time_offs`, {
          params: {
            path: { ...path, branch_id: branchId, professional_id: professionalId },
            query: LIST_PAGE,
          },
        }),
      ),
    enabled,
    throwOnError: false,
  });
}

export function useCreateProfessionalTimeOff(branchId: string, professionalId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (body: TimeOffInput) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/professionals/{professional_id}/time_offs`, {
          params: {
            path: { ...path, branch_id: branchId, professional_id: professionalId },
            header: CSRF,
          },
          body,
        }),
      ),
    meta: { silent: true },
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: professionalKeys.timeOffs(organizationId, companyId, branchId, professionalId),
      }),
  });
}

export function useDeleteProfessionalTimeOff(branchId: string, professionalId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (timeOffId: string) =>
      unwrap(
        client.DELETE(
          `${BASE}/branches/{branch_id}/professionals/{professional_id}/time_offs/{professional_time_off_id}`,
          {
            params: {
              path: {
                ...path,
                branch_id: branchId,
                professional_id: professionalId,
                professional_time_off_id: timeOffId,
              },
              header: CSRF,
            },
          },
        ),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: professionalKeys.timeOffs(organizationId, companyId, branchId, professionalId),
      }),
  });
}

/**
 * Absences of a professional through the COMPANY-scope route: the only way to reach those of someone with no branch.
 * A 403 (the permission is held only in a branch) must hide the section, not take the page down, so it never throws.
 */
export function useCompanyTimeOffsQuery(professionalId: string, { enabled = true } = {}) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: professionalKeys.companyTimeOffs(organizationId, companyId, professionalId),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/professionals/{professional_id}/time_offs`, {
          params: { path: { ...path, professional_id: professionalId }, query: LIST_PAGE },
        }),
      ),
    enabled,
    throwOnError: false,
    retry: false,
  });
}

export function useDeleteCompanyTimeOff(professionalId: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (timeOffId: string) =>
      unwrap(
        client.DELETE(
          `${BASE}/professionals/{professional_id}/time_offs/{professional_time_off_id}`,
          {
            params: {
              path: {
                ...path,
                professional_id: professionalId,
                professional_time_off_id: timeOffId,
              },
              header: CSRF,
            },
          },
        ),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({
        queryKey: professionalKeys.companyTimeOffs(organizationId, companyId, professionalId),
      }),
  });
}
