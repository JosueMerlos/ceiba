import i18next, { type BackendModule, type i18n } from "i18next";
import { initReactI18next } from "react-i18next";
import { defaultLocale } from "./config";
import type { esNI } from "./locales/es-NI";
import { auth } from "./locales/es-NI/auth";
import { common } from "./locales/es-NI/common";
import { errors } from "./locales/es-NI/errors";
import { shell } from "./locales/es-NI/shell";

export { Trans, useTranslation, I18nextProvider } from "react-i18next";
export { defaultLocale } from "./config";
export {
  formatClock,
  formatCurrency,
  formatDate,
  formatDateTime,
  formatNumber,
  formatPlainDate,
  formatTime,
} from "./formats";
export type { i18n as I18n, TFunction } from "i18next";

/** Any i18next `t` (from an instance or `useTranslation([...])`), whatever its key typing. */
export type AnyTranslate = (...args: never[]) => unknown;

/** `t` with string keys, for dynamic keys (e.g. an API error `code`). */
export type Translate = (key: string, options?: object) => string;

/** Widens a typed `t` to `Translate`. Fine-grained typing is lost: use only with dynamic keys. */
export const translator = (t: AnyTranslate): Translate => t as unknown as Translate;

type Catalog = typeof esNI;

// Typed keys: a key missing from the catalog does not compile. Typing sees the WHOLE catalog (type-only import), even
// though at runtime each module's namespace arrives with its route.
declare module "i18next" {
  interface CustomTypeOptions {
    defaultNS: "common";
    resources: Catalog;
  }
}

/** What the shell renders at startup (login, layout, error pages): the only texts in the critical JS. */
const startupCatalog = { common, auth, shell, errors } satisfies Partial<Catalog>;

/** A screen or module namespace: it is loaded with its lazy route, not at startup. */
export type LazyNamespace = Exclude<keyof Catalog, keyof typeof startupCatalog>;

// One `import()` per namespace, so Vite emits each in its own chunk. Typed against the catalog: a namespace added to
// locales/es-NI/index.ts without its loader does not compile.
const loaders: { [N in LazyNamespace]: () => Promise<Catalog[N]> } = {
  appointments: () => import("./locales/es-NI/appointments").then((file) => file.appointments),
  booking: () => import("./locales/es-NI/booking").then((file) => file.booking),
  branding: () => import("./locales/es-NI/branding").then((file) => file.branding),
  customers: () => import("./locales/es-NI/customers").then((file) => file.customers),
  imports: () => import("./locales/es-NI/imports").then((file) => file.imports),
};

const lazyNamespaces = Object.keys(loaders) as LazyNamespace[];

/**
 * Starts downloading namespaces without an i18n instance (e.g. in parallel with a route's chunk). The module cache
 * makes the instance's later load of the same namespace immediate.
 */
export function preloadNamespaces(namespaces: readonly LazyNamespace[]): Promise<unknown> {
  return Promise.all(namespaces.map((namespace) => loaders[namespace]()));
}

const isLazyNamespace = (namespace: string): namespace is LazyNamespace =>
  Object.hasOwn(loaders, namespace);

/** i18next backend over the loaders: `loadNamespaces` and `useTranslation` (with Suspense) fetch through it. */
const catalogBackend: BackendModule = {
  type: "backend",
  init: () => {},
  read(_language, namespace, callback) {
    if (!isLazyNamespace(namespace)) {
      callback(new Error(`Namespace de i18n desconocido: ${namespace}`), false);
      return;
    }
    loaders[namespace]().then(
      (data) => callback(null, data),
      (error: unknown) =>
        callback(error instanceof Error ? error : new Error(String(error)), false),
    );
  },
};

export interface CreateI18nOptions {
  /** "throw" fails on a missing key (tests); by default it just returns the key and warns. */
  onMissingKey?: "throw" | "warn";
  /**
   * Lazy namespaces loaded before the promise resolves. "all" loads the whole catalog: component tests that mount a
   * module screen without going through its route. The app leaves it empty: routes load their own.
   */
  preload?: readonly LazyNamespace[] | "all";
  /** Lazy namespaces the app ships in its own startup JS, so they need no request (booking: its page). */
  bundled?: Partial<Pick<Catalog, LazyNamespace>>;
}

/** Creates a NEW i18next instance (nothing global: each test and app has its own). */
export async function createI18n({
  onMissingKey = "warn",
  preload = [],
  bundled = {},
}: CreateI18nOptions = {}): Promise<i18n> {
  const instance = i18next.createInstance();
  const initial = { ...startupCatalog, ...bundled };
  const preloaded = preload === "all" ? lazyNamespaces : preload;
  await instance
    .use(catalogBackend)
    .use(initReactI18next)
    .init({
      lng: defaultLocale,
      fallbackLng: defaultLocale,
      supportedLngs: [defaultLocale],
      resources: { [defaultLocale]: initial },
      // Bundled resources plus the backend for whatever is missing.
      partialBundledLanguages: true,
      defaultNS: "common",
      // `ns` is what init waits for: the bundled namespaces plus the requested preloads.
      ns: [...new Set([...Object.keys(initial), ...preloaded])],
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
