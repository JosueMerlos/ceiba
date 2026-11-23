import { useMemo } from "react";
import { useCan } from "../../../platform/permissions/can";

/** What this user may do on the agenda, in the branch of the context. It only mirrors /me: the API decides. */
export function useAgendaPermissions() {
  const can = useCan();
  return useMemo(() => {
    const readsBranch = can("appointments.appointment.read");
    return {
      readsBranch,
      canCreate: can("appointments.appointment.create"),
      appointment: {
        manage: can("appointments.appointment.update"),
        own: can("appointments.appointment.update_own"),
      },
      readsProfessionals: can("appointments.professional.read"),
      readsResources: readsBranch && can("appointments.resource.read"),
      readsSchedules: can("appointments.schedule.read"),
      readsOwnSchedule: can("appointments.schedule.read_own"),
      readsAbsences: can("appointments.time_off.read"),
    };
  }, [can]);
}
