import { isApiError, unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { StatusAction } from "../lib/agenda-actions";
import type { PlainDate } from "../lib/agenda-time";
import { agendaKeys } from "./agenda";
import { APPOINTMENTS_BASE as BASE, CSRF, useCatalogScope } from "./shared";

type Schemas = components["schemas"];
export type AppointmentDetail = Schemas["AppointmentDetail"];
export type AppointmentInput = Schemas["AppointmentInput"];
export type AvailabilitySlot = Schemas["AvailabilitySlot"];
export type AgendaCustomer = Schemas["Customer"];
export type CancellationReason = NonNullable<Schemas["Appointment"]["cancellation_reason"]>;

const CUSTOMERS =
  "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/customers";
const MAX_CHAIN = 20;
const CUSTOMER_RESULTS = 10;
const PHONE_LIKE = /^[\d\s()+-]+$/;

function useBranchScope(branchId: string) {
  const scope = useCatalogScope();
  return { ...scope, branchPath: { ...scope.path, branch_id: branchId } };
}

/** After any write, whatever its outcome: the agenda may have changed under the user. */
function useRefreshAgenda() {
  const queryClient = useQueryClient();
  const { organizationId, companyId } = useCatalogScope();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: agendaKeys.all(organizationId, companyId) }),
      queryClient.invalidateQueries({
        queryKey: agendaKeys.availability(organizationId, companyId),
      }),
      queryClient.invalidateQueries({ queryKey: agendaKeys.details(organizationId, companyId) }),
    ]);
}

export function useBookAppointment(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  const refresh = useRefreshAgenda();
  return useMutation({
    mutationFn: ({ body, key }: { body: AppointmentInput; key: string }) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/appointments`, {
          params: { path: branchPath, header: { ...CSRF, "Idempotency-Key": key } },
          body,
        }),
      ),
    onSettled: refresh,
  });
}

export function useStatusAction(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  const refresh = useRefreshAgenda();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: StatusAction }) => {
      const params = { path: { ...branchPath, appointment_id: id }, header: CSRF };
      const base = `${BASE}/branches/{branch_id}/appointments/{appointment_id}` as const;
      switch (action) {
        case "confirm":
          return unwrap(client.POST(`${base}/confirm`, { params }));
        case "check_in":
          return unwrap(client.POST(`${base}/check_in`, { params }));
        case "complete":
          return unwrap(client.POST(`${base}/complete`, { params }));
        case "no_show":
          return unwrap(client.POST(`${base}/no_show`, { params }));
      }
    },
    onSettled: refresh,
  });
}

export function useCancelAppointment(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  const refresh = useRefreshAgenda();
  return useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: CancellationReason }) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/appointments/{appointment_id}/cancel`, {
          params: { path: { ...branchPath, appointment_id: id }, header: CSRF },
          body: { reason },
        }),
      ),
    onSettled: refresh,
  });
}

export function useRescheduleAppointment(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  const refresh = useRefreshAgenda();
  return useMutation({
    mutationFn: ({
      id,
      key,
      body,
    }: {
      id: string;
      key: string;
      body: { starts_at: string; professional_id?: string };
    }) =>
      unwrap(
        client.POST(`${BASE}/branches/{branch_id}/appointments/{appointment_id}/reschedule`, {
          params: {
            path: { ...branchPath, appointment_id: id },
            header: { ...CSRF, "Idempotency-Key": key },
          },
          body,
        }),
      ),
    onSettled: refresh,
  });
}

export function useUpdateNotes(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  const refresh = useRefreshAgenda();
  return useMutation({
    mutationFn: ({
      id,
      notes,
      lockVersion,
    }: {
      id: string;
      notes: string | null;
      lockVersion: number;
    }) =>
      unwrap(
        client.PATCH(`${BASE}/branches/{branch_id}/appointments/{appointment_id}`, {
          params: { path: { ...branchPath, appointment_id: id }, header: CSRF },
          body: { notes, lock_version: lockVersion },
        }),
      ),
    onSettled: refresh,
  });
}

export function useAppointmentDetail(branchId: string, id: string, enabled: boolean) {
  const client = useApiClient();
  const { organizationId, companyId, branchPath } = useBranchScope(branchId);
  return useQuery({
    queryKey: [...agendaKeys.details(organizationId, companyId), branchId, id],
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/appointments/{appointment_id}`, {
          params: { path: { ...branchPath, appointment_id: id } },
        }),
      ),
    enabled,
    throwOnError: false,
  });
}

/** The appointments this one was moved from, nearest first. A link the user may not read simply ends the chain. */
export function useRescheduleChain(
  branchId: string,
  firstOriginId: string | null,
  enabled: boolean,
) {
  const client = useApiClient();
  const { organizationId, companyId, branchPath } = useBranchScope(branchId);
  return useQuery({
    queryKey: [...agendaKeys.details(organizationId, companyId), "chain", branchId, firstOriginId],
    queryFn: async () => {
      const chain: AppointmentDetail[] = [];
      let next = firstOriginId;
      while (next && chain.length < MAX_CHAIN) {
        try {
          const { data } = await unwrap(
            client.GET(`${BASE}/branches/{branch_id}/appointments/{appointment_id}`, {
              params: { path: { ...branchPath, appointment_id: next } },
            }),
          );
          chain.push(data);
          next = data.rescheduled_from_id ?? null;
        } catch (error) {
          if (isApiError(error) && (error.status === 403 || error.status === 404)) break;
          throw error;
        }
      }
      return chain;
    },
    enabled: enabled && !!firstOriginId,
    throwOnError: false,
  });
}

export function useAvailabilityQuery({
  branchId,
  serviceIds,
  professionalId,
  date,
}: {
  branchId: string;
  serviceIds: readonly string[];
  professionalId: string | null;
  date: PlainDate;
}) {
  const client = useApiClient();
  const { organizationId, companyId, branchPath } = useBranchScope(branchId);
  const services = serviceIds.join(",");
  return useQuery({
    queryKey: [
      ...agendaKeys.availability(organizationId, companyId),
      branchId,
      services,
      professionalId,
      date,
    ],
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/availability`, {
          params: {
            path: branchPath,
            query: {
              service_ids: services,
              professional_id: professionalId ?? "",
              from: date,
              to: date,
            },
          },
        }),
      ),
    enabled: !!professionalId && serviceIds.length > 0,
    retry: false,
    throwOnError: false,
  });
}

export function useCustomerSearch(branchId: string, term: string) {
  const client = useApiClient();
  const { organizationId, companyId, branchPath } = useBranchScope(branchId);
  const query = term.trim();
  const filter = PHONE_LIKE.test(query) ? { phone: query } : { name_prefix: query };
  return useQuery({
    queryKey: agendaKeys.catalog(organizationId, companyId, "customers", branchId, query),
    queryFn: () =>
      unwrap(
        client.GET(CUSTOMERS, {
          params: { path: branchPath, query: { ...filter, limit: CUSTOMER_RESULTS } },
        }),
      ),
    enabled: query.length >= 2,
    throwOnError: false,
  });
}

// Silent: the form shows the failure next to its fields.
export function useCreateCustomer(branchId: string) {
  const client = useApiClient();
  const { branchPath } = useBranchScope(branchId);
  return useMutation({
    mutationFn: (body: { full_name: string; phone_e164: string }) =>
      unwrap(client.POST(CUSTOMERS, { params: { path: branchPath, header: CSRF }, body })),
    meta: { silent: true },
  });
}
