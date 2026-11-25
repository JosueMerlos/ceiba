import type { MinuteRange } from "../../lib/agenda-model";
import {
  clockOfMinutes,
  minutesOfWall,
  type PlainDate,
  type WallClock,
} from "../../lib/agenda-time";

const DAY_MINUTES = 24 * 60;

interface Busy {
  resourceId: string;
  start: WallClock;
  end: WallClock;
}

export interface FreeSlot {
  start: WallClock;
  minutes: number;
}

/** Minutes of `wall` from the start of `date`; another day lands before 0 or after the day's last minute. */
function minutesFrom(date: PlainDate, wall: WallClock) {
  const day = wall.slice(0, 10);
  if (day === date) return minutesOfWall(wall);
  return day < date ? -1 : DAY_MINUTES + 1;
}

/**
 * The gaps of one person (or resource) on a day: open time with no appointment, closed hour or absence, at least
 * `minMinutes` long, and none before `notBefore` (the current minute, today) rounded up to that step. Everything is the
 * branch's wall clock. Service buffers are not known here, so a gap right after an appointment may still be refused by
 * the availability the booking form asks for.
 */
export function freeSlots({
  resourceId,
  date,
  range,
  busy,
  minMinutes,
  notBefore = 0,
}: {
  resourceId: string;
  date: PlainDate;
  range: MinuteRange;
  busy: readonly Busy[];
  minMinutes: number;
  notBefore?: number;
}): FreeSlot[] {
  const taken = busy
    .filter((item) => item.resourceId === resourceId)
    .map((item) => [minutesFrom(date, item.start), minutesFrom(date, item.end)] as const)
    .filter(([start, end]) => end > range.startMinute && start < range.endMinute)
    .sort((a, b) => a[0] - b[0]);
  const slots: FreeSlot[] = [];
  let cursor = Math.max(range.startMinute, Math.ceil(notBefore / minMinutes) * minMinutes);
  const keep = (until: number) => {
    if (until - cursor >= minMinutes) {
      slots.push({ start: `${date}T${clockOfMinutes(cursor)}`, minutes: until - cursor });
    }
  };
  for (const [start, end] of taken) {
    if (start > cursor) keep(Math.min(start, range.endMinute));
    cursor = Math.max(cursor, end);
  }
  if (cursor < range.endMinute) keep(range.endMinute);
  return slots;
}
