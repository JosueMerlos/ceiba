import i18next, { type i18n } from "i18next";
import { initReactI18next } from "react-i18next";
import { defaultLocale } from "./config";
import { esNI } from "./locales/es-NI";

export { Trans, useTranslation, I18nextProvider } from "react-i18next";
export { defaultLocale } from "./config";
export { formatCurrency, formatDate, formatDateTime, formatNumber, formatTime } from "./formats";
export type { i18n as I18n, TFunction } from "i18next";

/** Any i18next `t` (from an instance or `useTranslation([...])`), whatever its key typing. */
export type AnyTranslate = (...args: never[]) => unknown;

/** `t` with string keys, for dynamic keys (e.g. an API error `code`). */
export type Translate = (key: string, options?: object) => string;

/** Widens a typed `t` to `Translate`. Fine-grained typing is lost: use only with dynamic keys. */
export const translator = (t: AnyTranslate): Translate => t as unknown as Translate;

export const resources = { [defaultLocale]: esNI } as const;

// Typed keys: a key missing from the catalog does not compile.
declare module "i18next" {
  interface CustomTypeOptions {
    defaultNS: "common";
    resources: typeof esNI;
  }
}

export interface CreateI18nOptions {
  /** "throw" fails on a missing key (tests); by default it just returns the key and warns. */
  onMissingKey?: "throw" | "warn";
}

/** Creates a NEW i18next instance (nothing global: each test and app has its own). */
export async function createI18n({ onMissingKey = "warn" }: CreateI18nOptions = {}): Promise<i18n> {
  const instance = i18next.createInstance();
  await instance.use(initReactI18next).init({
    lng: defaultLocale,
    fallbackLng: defaultLocale,
    supportedLngs: [defaultLocale],
    resources,
    defaultNS: "common",
    ns: Object.keys(esNI),
    interpolation: { escapeValue: false }, // React already escapes
    returnNull: false,
    saveMissing: true,
    missingKeyHandler: (_languages, namespace, key, _fallback, _update, options) => {
      // With an explicit `defaultValue` the caller already handles absence (e.g. an API code without translation).
      if (options?.defaultValue !== undefined) return;
      const message = `Clave de i18n inexistente: ${namespace}:${key}`;
      if (onMissingKey === "throw") throw new Error(message);
      console.warn(message);
    },
  });
  return instance;
}
