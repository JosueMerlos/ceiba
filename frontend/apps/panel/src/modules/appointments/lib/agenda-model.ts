import type { components } from "@ceiba/api-client";
import { ACTIVE_STATUSES } from "./agenda-status";
import {
  clockOfMinutes,
  minutesOfClock,
  minutesOfWall,
  toWallClock,
  weekdayOf,
  type PlainDate,
  type WallClock,
} from "./agenda-time";

type Schemas = components["schemas"];
export type AgendaAppointment = Schemas["AgendaAppointment"];
type WeeklySlot = Schemas["WeeklyScheduleSlot"];
type TimeOff = Schemas["TimeOff"];

/** Minutes since local midnight: [start, end). */
export type Interval = readonly [number, number];

export interface MinuteRange {
  startMinute: number;
  endMinute: number;
}

export interface AgendaBlock {
  resourceId: string;
  start: WallClock;
  end: WallClock;
}

export interface AgendaColumn {
  id: string;
  title: string;
}

/** The column of the appointments whose services need no resource. */
export const NO_RESOURCE = "sin-recurso";

const DEFAULT_RANGE: MinuteRange = { startMinute: 8 * 60, endMinute: 18 * 60 };
const HOUR = 60;
const ARRIVAL_WINDOW_MS = 60 * 60_000;
// Someone running late still has to be checked in from the arrivals panel.
const LATE_ARRIVAL_MS = 30 * 60_000;
const FREED_SLOT = new Set<AgendaAppointment["status"]>(["cancelled", "rescheduled"]);

export const visibleAppointments = (appointments: readonly AgendaAppointment[]) =>
  appointments.filter((appointment) => !FREED_SLOT.has(appointment.status));

/** Who is assigned to the branch, plus anyone with an appointment there: a former assignee's bookings must stay visible. */
export function mergeProfessionalColumns({
  branchId,
  professionals,
  appointments,
  nameOf,
}: {
  branchId: string;
  professionals: readonly { id: string; branch_ids: readonly string[] }[];
  appointments: readonly AgendaAppointment[];
  nameOf(id: string): string;
}): AgendaColumn[] {
  const ids = new Set(
    professionals
      .filter((person) => person.branch_ids.includes(branchId))
      .map((person) => person.id),
  );
  for (const { professional_id: id } of appointments) ids.add(id);
  return [...ids].map((id) => ({ id, title: nameOf(id) }));
}

const slotsOn = (slots: readonly WeeklySlot[], weekday: number): Interval[] =>
  slots
    .filter((slot) => slot.weekday === weekday)
    .map(
      (slot) => [minutesOfClock(slot.starts_at_local), minutesOfClock(slot.ends_at_local)] as const,
    )
    .sort((a, b) => a[0] - b[0]);

function intersect(first: readonly Interval[], second: readonly Interval[]): Interval[] {
  return first.flatMap(([startA, endA]) =>
    second.flatMap(([startB, endB]): Interval[] => {
      const start = Math.max(startA, startB);
      const end = Math.min(endA, endB);
      return start < end ? [[start, end]] : [];
    }),
  );
}

/** A professional works inside the branch's hours; without hours of their own they are closed. */
export function openForProfessional(
  branch: readonly WeeklySlot[] | null,
  own: readonly WeeklySlot[],
  weekday: number,
): Interval[] {
  const mine = slotsOn(own, weekday);
  return branch ? intersect(slotsOn(branch, weekday), mine) : mine;
}

/** A resource without hours of its own follows the branch. */
export function openForResource(
  branch: readonly WeeklySlot[],
  own: readonly WeeklySlot[],
  weekday: number,
): Interval[] {
  const opening = slotsOn(branch, weekday);
  return own.length === 0 ? opening : intersect(opening, slotsOn(own, weekday));
}

function closedWithin(open: readonly Interval[], { startMinute, endMinute }: MinuteRange) {
  const closed: Interval[] = [];
  let cursor = startMinute;
  for (const [start, end] of open) {
    if (start > cursor) closed.push([cursor, Math.min(start, endMinute)]);
    cursor = Math.max(cursor, end);
  }
  if (cursor < endMinute) closed.push([cursor, endMinute]);
  return closed.filter(([start, end]) => start < end);
}

export interface BlockColumn {
  id: string;
  openOn(weekday: number): readonly Interval[];
  timeOffs: readonly TimeOff[];
}

/** Everything inside the visible hours that cannot be booked: closed hours and absences, per column and day. */
export function closedBlocks({
  columns,
  days,
  timeZone,
  range,
}: {
  columns: readonly BlockColumn[];
  days: readonly PlainDate[];
  timeZone: string;
  range: MinuteRange;
}): AgendaBlock[] {
  return columns.flatMap((column) =>
    days.flatMap((day) => {
      const at = (minutes: number): WallClock => `${day}T${clockOfMinutes(minutes)}`;
      const dayStart = at(range.startMinute);
      const dayEnd = at(range.endMinute);
      const closed = closedWithin(column.openOn(weekdayOf(day)), range).map(
        ([start, end]): AgendaBlock => ({
          resourceId: column.id,
          start: at(start),
          end: at(end),
        }),
      );
      const absent = column.timeOffs.flatMap((timeOff): AgendaBlock[] => {
        const startWall = toWallClock(timeOff.starts_at, timeZone);
        const endWall = toWallClock(timeOff.ends_at, timeZone);
        const start = startWall > dayStart ? startWall : dayStart;
        const end = endWall < dayEnd ? endWall : dayEnd;
        return start < end ? [{ resourceId: column.id, start, end }] : [];
      });
      return [...closed, ...absent];
    }),
  );
}

/** The hours to draw, in whole hours: the opening hours, stretched so no appointment outside them is hidden. */
export function timeRange({
  openings,
  appointments,
  timeZone,
}: {
  openings: readonly Interval[];
  appointments: readonly AgendaAppointment[];
  timeZone: string;
}): MinuteRange {
  const spans: Interval[] = [
    ...openings,
    ...appointments.map((appointment): Interval => {
      const start = toWallClock(appointment.starts_at, timeZone);
      const end = toWallClock(appointment.ends_at, timeZone);
      // An appointment that crosses midnight is drawn up to the end of its first day.
      return [
        minutesOfWall(start),
        end.slice(0, 10) === start.slice(0, 10) ? minutesOfWall(end) : 24 * HOUR,
      ];
    }),
  ];
  if (spans.length === 0) return DEFAULT_RANGE;
  const startMinute = Math.floor(Math.min(...spans.map(([start]) => start)) / HOUR) * HOUR;
  const endMinute = Math.ceil(Math.max(...spans.map(([, end]) => end)) / HOUR) * HOUR;
  // The calendar cannot draw an empty range.
  return { startMinute, endMinute: Math.max(endMinute, startMinute + HOUR) };
}

/** Who is expected within the next hour, or is up to half an hour late, soonest first. */
export function upcomingArrivals(appointments: readonly AgendaAppointment[], now: Date) {
  const from = now.getTime();
  return appointments
    .filter((appointment) => {
      const start = Date.parse(appointment.starts_at);
      return (
        ACTIVE_STATUSES.includes(appointment.status) &&
        start >= from - LATE_ARRIVAL_MS &&
        start < from + ARRIVAL_WINDOW_MS
      );
    })
    .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at));
}

/**
 * Closes the whole visible day of every column whose hours have not arrived yet. A screen that offers free gaps must not
 * offer time it cannot tell is open.
 */
export function closeUnknownHours({
  blocks,
  columnIds,
  knownIds,
  days,
  range,
}: {
  blocks: readonly AgendaBlock[];
  columnIds: readonly string[];
  knownIds: ReadonlySet<string>;
  days: readonly PlainDate[];
  range: MinuteRange;
}): readonly AgendaBlock[] {
  const unknown = columnIds.filter((id) => !knownIds.has(id));
  if (unknown.length === 0) return blocks;
  const start = clockOfMinutes(range.startMinute);
  const end = clockOfMinutes(range.endMinute);
  return [
    ...blocks,
    ...unknown.flatMap((resourceId) =>
      days.map((day) => ({ resourceId, start: `${day}T${start}`, end: `${day}T${end}` })),
    ),
  ];
}
