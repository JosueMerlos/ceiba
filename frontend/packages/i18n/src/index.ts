import i18next, { type i18n } from "i18next";
import { initReactI18next } from "react-i18next";
import { defaultLocale } from "./config";
import { esNI } from "./locales/es-NI";

export { Trans, useTranslation, I18nextProvider } from "react-i18next";
export { defaultLocale } from "./config";
export { formatCurrency, formatDate, formatDateTime, formatNumber, formatTime } from "./formats";
export type { i18n as I18n, TFunction } from "i18next";

export const resources = { [defaultLocale]: esNI } as const;

// Claves tipadas: una clave que no existe en el catálogo no compila.
declare module "i18next" {
  interface CustomTypeOptions {
    defaultNS: "common";
    resources: typeof esNI;
  }
}

export interface CreateI18nOptions {
  /** "throw" falla ante una clave inexistente (pruebas); por defecto solo la devuelve y avisa. */
  onMissingKey?: "throw" | "warn";
}

/** Crea una instancia NUEVA de i18next (nada global: cada test y cada app tiene la suya). */
export async function createI18n({ onMissingKey = "warn" }: CreateI18nOptions = {}): Promise<i18n> {
  const instance = i18next.createInstance();
  await instance.use(initReactI18next).init({
    lng: defaultLocale,
    fallbackLng: defaultLocale,
    supportedLngs: [defaultLocale],
    resources,
    defaultNS: "common",
    ns: Object.keys(esNI),
    interpolation: { escapeValue: false }, // React ya escapa
    returnNull: false,
    saveMissing: true,
    missingKeyHandler: (_languages, namespace, key) => {
      const message = `Clave de i18n inexistente: ${namespace}:${key}`;
      if (onMissingKey === "throw") throw new Error(message);
      console.warn(message);
    },
  });
  return instance;
}
