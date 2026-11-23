import { localToUtcIso, utcToLocalInput } from "./zoned-time";

/** A calendar day of the branch, "2026-11-18". */
export type PlainDate = string;
/** A wall-clock time of the branch, "2026-11-18T09:30:00". */
export type WallClock = string;

const DAY_MS = 86_400_000;
const PLAIN_DATE = /^\d{4}-\d{2}-\d{2}$/;
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

/** A real calendar day: "2026-13-45" and "2026-02-30" are not. */
export function isPlainDate(value: string): value is PlainDate {
  if (!PLAIN_DATE.test(value)) return false;
  const time = utcMidnight(value);
  return !Number.isNaN(time) && plainDate(time) === value;
}

export const dayInZone = (iso: string, timeZone: string): PlainDate =>
  toWallClock(iso, timeZone).slice(0, 10);

export const todayInZone = (timeZone: string, now: Date = new Date()): PlainDate =>
  dayInZone(now.toISOString(), timeZone);

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

const clockFormat = (timeZone: string) =>
  new Intl.DateTimeFormat("es-NI", { hour: "numeric", minute: "2-digit", hour12: true, timeZone });

/** "9:30": the compact time of the agenda's cards, whose column already says whether it is morning or afternoon. */
export const shortClock = (iso: string, timeZone: string) =>
  clockFormat(timeZone)
    .formatToParts(new Date(iso))
    .filter((part) => part.type === "hour" || part.type === "minute")
    .map((part) => part.value)
    .join(":");
