import { unwrap, useApiClient, type ApiClient, type components } from "@ceiba/api-client";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { StatusAction } from "../lib/agenda-actions";
import { agendaKeys } from "./agenda";
import { APPOINTMENTS_BASE as BASE, CSRF, useCatalogScope } from "./shared";

type Schemas = components["schemas"];
export type AppointmentInput = Schemas["AppointmentInput"];
export type CancellationReason = NonNullable<Schemas["Appointment"]["cancellation_reason"]>;

const APPOINTMENTS = `${BASE}/branches/{branch_id}/appointments` as const;
const APPOINTMENT = `${APPOINTMENTS}/{appointment_id}` as const;

interface WriteContext {
  client: ApiClient;
  branchPath: { organization_id: string; company_id: string; branch_id: string };
}

/** A write on the agenda. Whatever its outcome, the agenda is fetched again: it may have changed under the user. */
function useAgendaWrite<Variables, Result>(
  branchId: string,
  write: (context: WriteContext, variables: Variables) => Promise<Result>,
) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  const { organizationId, companyId, path } = useCatalogScope();
  return useMutation({
    mutationFn: (variables: Variables) =>
      write({ client, branchPath: { ...path, branch_id: branchId } }, variables),
    onSettled: () =>
      Promise.all(
        [agendaKeys.all, agendaKeys.availability, agendaKeys.details].map((key) =>
          queryClient.invalidateQueries({ queryKey: key(organizationId, companyId) }),
        ),
      ),
  });
}

export const useBookAppointment = (branchId: string) =>
  useAgendaWrite(
    branchId,
    ({ client, branchPath }, { body, key }: { body: AppointmentInput; key: string }) =>
      unwrap(
        client.POST(APPOINTMENTS, {
          params: { path: branchPath, header: { ...CSRF, "Idempotency-Key": key } },
          body,
        }),
      ),
  );

export const useStatusAction = (branchId: string) =>
  useAgendaWrite(
    branchId,
    ({ client, branchPath }, { id, action }: { id: string; action: StatusAction }) => {
      const params = { path: { ...branchPath, appointment_id: id }, header: CSRF };
      switch (action) {
        case "confirm":
          return unwrap(client.POST(`${APPOINTMENT}/confirm`, { params }));
        case "check_in":
          return unwrap(client.POST(`${APPOINTMENT}/check_in`, { params }));
        case "complete":
          return unwrap(client.POST(`${APPOINTMENT}/complete`, { params }));
        case "no_show":
          return unwrap(client.POST(`${APPOINTMENT}/no_show`, { params }));
      }
    },
  );

export const useCancelAppointment = (branchId: string) =>
  useAgendaWrite(
    branchId,
    ({ client, branchPath }, { id, reason }: { id: string; reason: CancellationReason }) =>
      unwrap(
        client.POST(`${APPOINTMENT}/cancel`, {
          params: { path: { ...branchPath, appointment_id: id }, header: CSRF },
          body: { reason },
        }),
      ),
  );

export interface RescheduleVariables {
  id: string;
  key: string;
  body: { starts_at: string; professional_id?: string };
}

export const useRescheduleAppointment = (branchId: string) =>
  useAgendaWrite(branchId, ({ client, branchPath }, { id, key, body }: RescheduleVariables) =>
    unwrap(
      client.POST(`${APPOINTMENT}/reschedule`, {
        params: {
          path: { ...branchPath, appointment_id: id },
          header: { ...CSRF, "Idempotency-Key": key },
        },
        body,
      }),
    ),
  );

export const useUpdateNotes = (branchId: string) =>
  useAgendaWrite(
    branchId,
    (
      { client, branchPath },
      { id, notes, lockVersion }: { id: string; notes: string | null; lockVersion: number },
    ) =>
      unwrap(
        client.PATCH(APPOINTMENT, {
          params: { path: { ...branchPath, appointment_id: id }, header: CSRF },
          body: { notes, lock_version: lockVersion },
        }),
      ),
  );
