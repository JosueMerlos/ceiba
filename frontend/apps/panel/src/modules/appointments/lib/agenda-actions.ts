import type { AgendaAppointment } from "./agenda-model";
import { ACTIVE_STATUSES, type AppointmentStatus } from "./agenda-status";

export type StatusAction = "confirm" | "check_in" | "complete" | "no_show";

export interface AppointmentPermissions {
  /** May act on any appointment of the branch. */
  manage: boolean;
  /** May act on their own appointments, which are the only ones they are shown. */
  own: boolean;
}

export interface AppointmentActions {
  status: StatusAction[];
  canReschedule: boolean;
  canCancel: boolean;
}

// Mirrors the backend's transition table so the panel only offers what can work; the API still decides.
const STATUS_RULES: readonly { action: StatusAction; from: readonly AppointmentStatus[] }[] = [
  { action: "confirm", from: ["scheduled"] },
  { action: "check_in", from: ACTIVE_STATUSES },
  { action: "complete", from: ["checked_in"] },
  { action: "no_show", from: ACTIVE_STATUSES },
];

export function appointmentActions(
  appointment: Pick<AgendaAppointment, "status" | "starts_at">,
  { manage, own }: AppointmentPermissions,
  now: Date,
): AppointmentActions {
  const started = Date.parse(appointment.starts_at) <= now.getTime();
  const staffOnly = manage && ACTIVE_STATUSES.includes(appointment.status);
  return {
    status:
      manage || own
        ? STATUS_RULES.filter(
            ({ action, from }) =>
              from.includes(appointment.status) && (action !== "no_show" || started),
          ).map(({ action }) => action)
        : [],
    canReschedule: staffOnly,
    canCancel: staffOnly,
  };
}
