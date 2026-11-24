import type { AgendaBlock, MinuteRange } from "../../lib/agenda-model";
import type { StatusTone } from "../../lib/agenda-status";
import type { PlainDate, WallClock } from "../../lib/agenda-time";

/** How much of the day fits on screen: compact rows are shorter and hours narrower. */
export type AgendaDensity = "comfortable" | "compact";

export interface AgendaViewResource {
  id: string;
  title: string;
  /** Second line of the row (or, in the week, column) header. */
  detail: string;
}

export interface AgendaViewEvent {
  id: string;
  resourceId: string;
  start: WallClock;
  end: WallClock;
  tone: StatusTone;
  title: string;
  subtitle: string;
  meta: string;
  movable: boolean;
}

export interface AgendaSlot {
  /** UTC instant. */
  startsAt: string;
  resourceId: string | null;
}

export interface AgendaViewProps {
  mode: "day" | "week";
  date: PlainDate;
  /** The branch's zone: everything the calendar draws and returns is read in it, never in the browser's. */
  timeZone: string;
  resources: readonly AgendaViewResource[];
  events: readonly AgendaViewEvent[];
  blocks: readonly AgendaBlock[];
  range: MinuteRange;
  stepMinutes: number;
  /** Where the current-time line goes, when the visible range includes today. */
  now: WallClock | null;
  onSelectSlot?(slot: AgendaSlot): void;
  onOpenEvent?(id: string): void;
  /** Resolves false when the move was refused: the event goes back to where it was. */
  onMoveEvent?(id: string, to: AgendaSlot): Promise<boolean>;
}
