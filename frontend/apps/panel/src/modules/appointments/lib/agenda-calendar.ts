import type { AgendaViewEvent, AgendaViewResource } from "../components/agenda-view/types";
import type { AgendaLens } from "./agenda-lens";
import type { AgendaAppointment, AgendaColumn } from "./agenda-model";
import { STATUS_TONE } from "./agenda-status";
import { toWallClock } from "./agenda-time";

export interface AppointmentLabels {
  title: string;
  subtitle: string;
  meta: string;
}

export function toCalendarEvents({
  appointments,
  columns,
  lens,
  timeZone,
  labelsOf,
  canMove,
}: {
  appointments: readonly AgendaAppointment[];
  columns: readonly AgendaColumn[];
  lens: AgendaLens;
  timeZone: string;
  labelsOf(appointment: AgendaAppointment): AppointmentLabels;
  canMove(appointment: AgendaAppointment): boolean;
}): AgendaViewEvent[] {
  const columnIds = new Set(columns.map((column) => column.id));
  return appointments.map((appointment) => ({
    ...labelsOf(appointment),
    id: appointment.id,
    resourceId: lens.columnOf(appointment, columnIds),
    start: toWallClock(appointment.starts_at, timeZone),
    end: toWallClock(appointment.ends_at, timeZone),
    tone: STATUS_TONE[appointment.status],
    movable: lens.movable && canMove(appointment),
  }));
}

export function toCalendarResources(
  columns: readonly AgendaColumn[],
  events: readonly AgendaViewEvent[],
  countLabel: (count: number) => string,
): AgendaViewResource[] {
  const counts = new Map<string, number>();
  for (const { resourceId } of events) counts.set(resourceId, (counts.get(resourceId) ?? 0) + 1);
  return columns.map(({ id, title }) => ({ id, title, detail: countLabel(counts.get(id) ?? 0) }));
}
