import { createI18n, type CreateI18nOptions } from "@ceiba/i18n";
import { booking } from "@ceiba/i18n/locales/booking";

/**
 * The booking page's i18n: its namespace ships in the startup JS (a few hundred bytes), because fetching it on demand
 * would add a round trip before the first paint on a mobile network.
 */
export const createBookingI18n = (options: Omit<CreateI18nOptions, "bundled"> = {}) =>
  createI18n({ ...options, bundled: { booking } });
