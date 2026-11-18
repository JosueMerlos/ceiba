import { isApiError, unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useQuery } from "@tanstack/react-query";
import { agendaKeys } from "./agenda";
import { APPOINTMENTS_BASE as BASE, useCatalogScope } from "./shared";

export type AppointmentDetail = components["schemas"]["AppointmentDetail"];

const MAX_CHAIN = 20;
const DETAIL = `${BASE}/branches/{branch_id}/appointments/{appointment_id}` as const;

export function useAppointmentDetail(branchId: string, id: string, enabled: boolean) {
  const client = useApiClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.detail(organizationId, companyId, branchId, id),
    queryFn: () =>
      unwrap(
        client.GET(DETAIL, {
          params: { path: { ...path, branch_id: branchId, appointment_id: id } },
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
  const { organizationId, companyId, path } = useCatalogScope();
  return useQuery({
    queryKey: agendaKeys.chain(organizationId, companyId, branchId, firstOriginId),
    queryFn: async () => {
      const chain: AppointmentDetail[] = [];
      let next = firstOriginId;
      while (next && chain.length < MAX_CHAIN) {
        try {
          const { data } = await unwrap(
            client.GET(DETAIL, {
              params: { path: { ...path, branch_id: branchId, appointment_id: next } },
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
