import {
  NO_RESOURCE,
  openForProfessional,
  openForResource,
  type AgendaAppointment,
  type Interval,
} from "./agenda-model";

export type AgendaMode = "professionals" | "resources" | "week";
export const AGENDA_MODES: readonly AgendaMode[] = ["professionals", "resources", "week"];

type Slots = Parameters<typeof openForProfessional>[1];

/** Everything that differs between the agenda's views, so the rest of the screen has no branches on the mode. */
export interface AgendaLens {
  ownerKind: "professional" | "resource";
  columnOf(appointment: AgendaAppointment, columnIds: ReadonlySet<string>): string;
  openOn(branch: Slots | null, own: Slots, weekday: number): readonly Interval[];
  /** A resource is assigned by the booking engine, so its view cannot choose one by dragging. */
  movable: boolean;
}

const byProfessional: AgendaLens = {
  ownerKind: "professional",
  columnOf: (appointment) => appointment.professional_id,
  openOn: openForProfessional,
  movable: true,
};

const byResource: AgendaLens = {
  ownerKind: "resource",
  columnOf: ({ resource_id: id }, columnIds) => (id && columnIds.has(id) ? id : NO_RESOURCE),
  openOn: (branch, own, weekday) => (branch ? openForResource(branch, own, weekday) : []),
  movable: false,
};

export const AGENDA_LENSES: Record<AgendaMode, AgendaLens> = {
  professionals: byProfessional,
  resources: byResource,
  week: byProfessional,
};
