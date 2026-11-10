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

export function formatDate(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, { dateStyle: "long", timeZone }).format(
    toDate(value),
  );
}

export function formatTime(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, { timeStyle: "short", timeZone }).format(
    toDate(value),
  );
}

export function formatDateTime(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, {
    dateStyle: "long",
    timeStyle: "short",
    timeZone,
  }).format(toDate(value));
}
