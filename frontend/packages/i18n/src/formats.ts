import { defaultLocale } from "./config";

// Formatos con Intl, siempre en es-NI. Las fechas llevan SIEMPRE la zona de la sucursal (IANA), nunca la del navegador.
type Instant = Date | string | number;

const toDate = (value: Instant) => (value instanceof Date ? value : new Date(value));

export function formatNumber(value: number, options?: Intl.NumberFormatOptions): string {
  return new Intl.NumberFormat(defaultLocale, options).format(value);
}

// CLDR escribe el dólar como "USD" en es-NI; en Nicaragua se lee y se escribe "US$" (el córdoba sí sale como "C$").
const CURRENCY_SYMBOLS: Partial<Record<"NIO" | "USD", string>> = { USD: "US$" };

export function formatCurrency(amount: number, currency: "NIO" | "USD"): string {
  const parts = new Intl.NumberFormat(defaultLocale, { style: "currency", currency }).formatToParts(amount);
  const symbol = CURRENCY_SYMBOLS[currency];
  return parts.map((part) => (part.type === "currency" && symbol ? symbol : part.value)).join("");
}

export function formatDate(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, { dateStyle: "long", timeZone }).format(toDate(value));
}

export function formatTime(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, { timeStyle: "short", timeZone }).format(toDate(value));
}

export function formatDateTime(value: Instant, timeZone: string): string {
  return new Intl.DateTimeFormat(defaultLocale, {
    dateStyle: "long",
    timeStyle: "short",
    timeZone,
  }).format(toDate(value));
}
