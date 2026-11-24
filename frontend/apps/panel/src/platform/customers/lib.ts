import { defaultLocale } from "@ceiba/i18n";

const NICARAGUA = /^\+505(\d{4})(\d{4})$/;

/** A stored E.164 number as people read it: "+50588123456" -> "+505 8812 3456". Other countries stay as stored. */
export function formatPhone(e164: string): string {
  const match = NICARAGUA.exec(e164);
  return match ? `+505 ${match[1]} ${match[2]}` : e164;
}

/** "marzo de 2026", in the branch's time zone. */
export function formatMonth(instant: string, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, {
    month: "long",
    year: "numeric",
    timeZone,
  }).format(new Date(instant));
}

/** The branch-local calendar date of an instant, as the agenda's `date` parameter expects it (YYYY-MM-DD). */
export function localDate(instant: string, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date(instant));
}
