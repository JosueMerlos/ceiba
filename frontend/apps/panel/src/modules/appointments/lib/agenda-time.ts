import { localToUtcIso, utcToLocalInput } from "./zoned-time";

/** A calendar day of the branch, "2026-11-18". */
export type PlainDate = string;
/** A wall-clock time of the branch, "2026-11-18T09:30:00". */
export type WallClock = string;

const DAY_MS = 86_400_000;
const pad = (value: number) => String(value).padStart(2, "0");
const utcMidnight = (day: PlainDate) => Date.parse(`${day}T00:00:00Z`);
const plainDate = (ms: number) => new Date(ms).toISOString().slice(0, 10);

export const toWallClock = (iso: string, timeZone: string): WallClock =>
  `${utcToLocalInput(iso, timeZone)}:00`;

export const wallClockToInstant = (wall: WallClock, timeZone: string): string | null =>
  localToUtcIso(wall.slice(0, 16), timeZone);

/** The calendar hands back Dates whose LOCAL fields hold the branch's wall clock; the browser's zone plays no part. */
export function localDateToInstant(date: Date, timeZone: string): string | null {
  const day = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  return localToUtcIso(`${day}T${pad(date.getHours())}:${pad(date.getMinutes())}`, timeZone);
}

export const todayInZone = (timeZone: string, now: Date = new Date()): PlainDate =>
  toWallClock(now.toISOString(), timeZone).slice(0, 10);

export const addDays = (day: PlainDate, amount: number): PlainDate =>
  plainDate(utcMidnight(day) + amount * DAY_MS);

/** 0 is Sunday, as in the weekly schedules. */
export const weekdayOf = (day: PlainDate) => new Date(utcMidnight(day)).getUTCDay();

export const mondayOf = (day: PlainDate): PlainDate => addDays(day, -((weekdayOf(day) + 6) % 7));

export const minutesOfClock = (clock: string) =>
  Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3, 5));

export const minutesOfWall = (wall: WallClock) => minutesOfClock(wall.slice(11, 16));

export const clockOfMinutes = (minutes: number) =>
  `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}:00`;
