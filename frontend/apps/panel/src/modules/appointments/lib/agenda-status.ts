import type { AgendaAppointment } from "./agenda-model";

export type AppointmentStatus = AgendaAppointment["status"];
export type StatusTone = "pending" | "confirmed" | "arrived" | "done" | "missed";

/** The visual family of each status; cancelled and rescheduled appointments only show up in the detail. */
export const STATUS_TONE: Record<AppointmentStatus, StatusTone> = {
  scheduled: "pending",
  confirmed: "confirmed",
  checked_in: "arrived",
  completed: "done",
  no_show: "missed",
  cancelled: "done",
  rescheduled: "done",
};

export const LEGEND_STATUSES: readonly AppointmentStatus[] = [
  "confirmed",
  "scheduled",
  "checked_in",
  "completed",
  "no_show",
];
