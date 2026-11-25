import { defaultLocale } from "./config";

// Intl formats, always es-NI. Dates ALWAYS use the branch's (IANA) time zone, never the browser's.
type Instant = Date | string | number;

const toDate = (value: Instant) => (value instanceof Date ? value : new Date(value));

export function formatNumber(value: number, options?: Intl.NumberFormatOptions): string {
  return new Intl.NumberFormat(defaultLocale, options).format(value);
}

// CLDR writes the dollar as "USD" in es-NI; in Nicaragua it is read and written "US$" (the córdoba does come out as "C$").
const CURRENCY_SYMBOLS: Partial<Record<"NIO" | "USD", string>> = { USD: "US$" };

export function formatCurrency(amount: number, currency: "NIO" | "USD"): string {
  const parts = new Intl.NumberFormat(defaultLocale, { style: "currency", currency }).formatToParts(
    amount,
  );
  const symbol = CURRENCY_SYMBOLS[currency];
  return parts.map((part) => (part.type === "currency" && symbol ? symbol : part.value)).join("");
}

// ICU separates "9:00 a. m." with U+0020, U+00A0 or U+202F depending on the engine: one non-breaking space everywhere
// keeps the text identical in Node and every browser, and never wraps a time or a date.
const NBSP = "\u00a0";
const normalizeSpaces = (text: string) => text.replace(/[\s\u202f]+/g, NBSP);

/** One Intl formatter per zone for these options: building them is the expensive part. */
function formatterByZone(options: Intl.DateTimeFormatOptions) {
  const cache = new Map<string, Intl.DateTimeFormat>();
  return (timeZone: string) => {
    let format = cache.get(timeZone);
    if (!format) {
      format = new Intl.DateTimeFormat(defaultLocale, { ...options, timeZone });
      cache.set(timeZone, format);
    }
    return format;
  };
}

const timeFormat = formatterByZone({ hour: "numeric", minute: "2-digit", hour12: true });
const dateFormat = formatterByZone({
  weekday: "short",
  day: "numeric",
  month: "short",
  year: "numeric",
});

/** "9:00 a. m.": the time of an instant in the branch's zone. */
export function formatTime(value: Instant, timeZone: string): string {
  return normalizeSpaces(timeFormat(timeZone).format(toDate(value)));
}

/** "9:30 p. m." for a branch wall-clock time "21:30" (no zone involved). */
export function formatClock(clock: string): string {
  const [hours = 0, minutes = 0] = clock.split(":").map(Number);
  return normalizeSpaces(timeFormat("UTC").format(Date.UTC(1970, 0, 1, hours, minutes)));
}

/** "lun 14 dic 2026": the date of an instant in the branch's zone. */
export function formatDate(value: Instant, timeZone: string): string {
  // Built from parts: ICU puts a comma after the weekday ("lun, 14 dic 2026").
  const parts = Object.fromEntries(
    dateFormat(timeZone)
      .formatToParts(toDate(value))
      .map((part) => [part.type, part.value]),
  );
  return [parts.weekday, parts.day, parts.month, parts.year].join(NBSP);
}

/** "lun 14 dic 2026" for a calendar day "2026-12-14" (no zone may move it). */
export function formatPlainDate(day: string): string {
  return formatDate(`${day}T12:00:00Z`, "UTC");
}

/** "45 min", "1 h", "1 h 30 min": how long a service or a gap lasts. */
export function formatDuration(minutes: number): string {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`;
}

/** "lun 14 dic 2026, 9:00 a. m." */
export function formatDateTime(value: Instant, timeZone: string): string {
  return `${formatDate(value, timeZone)}, ${formatTime(value, timeZone)}`;
}
