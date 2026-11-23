import { unwrap, useApiClient, type components } from "@ceiba/api-client";
import { useQueries, useQuery, type UseQueryResult } from "@tanstack/react-query";
import { useMemo } from "react";
import type { PlainDate } from "../lib/agenda-time";
import { agendaKeys } from "./agenda";
import { scheduleQuery } from "./catalog";
import { everyProfessionalTimeOffQuery, professionalScheduleQuery } from "./professionals";
import { everyResourceTimeOffQuery, resourceScheduleQuery } from "./resources";
import { APPOINTMENTS_BASE as BASE, useCatalogScope } from "./shared";

type Schemas = components["schemas"];
type WeeklySlot = Schemas["WeeklyScheduleSlot"];
type TimeOff = Schemas["TimeOff"];
export type AvailabilitySlot = Schemas["AvailabilitySlot"];

export interface OwnerAvailability {
  slots: readonly WeeklySlot[];
  timeOffs: readonly TimeOff[];
}

type OwnerKind = "professional" | "resource";

const QUERIES = {
  professional: {
    schedule: professionalScheduleQuery,
    timeOffs: everyProfessionalTimeOffQuery,
  },
  resource: { schedule: resourceScheduleQuery, timeOffs: everyResourceTimeOffQuery },
};

const NOTHING_YET = new Map<string, never>();

// Published all at once: each partial result would redraw the whole calendar.
function combineOwners<T>(results: UseQueryResult<{ ownerId: string; value: T }>[]) {
  if (results.some((result) => result.isLoading)) return NOTHING_YET as ReadonlyMap<string, T>;
  return new Map(
    results.flatMap(({ data }) => (data ? [[data.ownerId, data.value] as const] : [])),
  );
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
  const scope = useCatalogScope();
  const queries = QUERIES[kind];
  const schedules = useQueries({
    queries: ownerIds.map((ownerId) => ({
      ...queries.schedule(client, scope, branchId, ownerId),
      select: ({ data }: { data: WeeklySlot[] }) => ({ ownerId, value: data }),
      enabled,
      retry: false,
      throwOnError: false,
    })),
    combine: combineOwners<WeeklySlot[]>,
  });
  const timeOffs = useQueries({
    queries: ownerIds.map((ownerId) => ({
      ...queries.timeOffs(client, scope, branchId, ownerId),
      select: (value: TimeOff[]) => ({ ownerId, value }),
      enabled,
      retry: false,
      throwOnError: false,
    })),
    combine: combineOwners<TimeOff[]>,
  });
  return useMemo(() => {
    const owners = new Map<string, OwnerAvailability>();
    for (const [ownerId, slots] of schedules) {
      const absences = timeOffs.get(ownerId);
      if (absences) owners.set(ownerId, { slots, timeOffs: absences });
    }
    return owners;
  }, [schedules, timeOffs]);
}

export function useAgendaBranchSchedule(branchId: string, enabled: boolean) {
  const client = useApiClient();
  const scope = useCatalogScope();
  return useQuery({ ...scheduleQuery(client, scope, branchId), enabled, throwOnError: false });
}

/** The free starts of one day for the chosen services and professional. */
export function useFreeSlots({
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
  const { organizationId, companyId, path } = useCatalogScope();
  const services = serviceIds.join(",");
  return useQuery({
    queryKey: agendaKeys.slots(organizationId, companyId, branchId, services, professionalId, date),
    queryFn: () =>
      unwrap(
        client.GET(`${BASE}/branches/{branch_id}/availability`, {
          params: {
            path: { ...path, branch_id: branchId },
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
