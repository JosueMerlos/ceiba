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

/** Booked and still ahead: what can be confirmed, moved or cancelled, and who is expected to arrive. */
export const ACTIVE_STATUSES: readonly AppointmentStatus[] = ["scheduled", "confirmed"];

export const LEGEND_STATUSES: readonly AppointmentStatus[] = [
  "confirmed",
  "scheduled",
  "checked_in",
  "completed",
  "no_show",
];
