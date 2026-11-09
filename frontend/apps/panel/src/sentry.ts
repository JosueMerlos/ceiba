import * as Sentry from "@sentry/react";
import type { ErrorEvent } from "@sentry/react";

// Variables de Vite (se fijan al construir). Sin VITE_SENTRY_DSN Sentry queda inactivo; en modo `test` también.
//   VITE_SENTRY_DSN          DSN del proyecto del panel
//   VITE_SENTRY_ENVIRONMENT  entorno en Sentry (por defecto, el modo de Vite)
//   VITE_APP_RELEASE         identificador del despliegue (el mismo SHA que APP_RELEASE del backend)
export interface SentryEnv {
  MODE: string;
  VITE_SENTRY_DSN?: string;
  VITE_SENTRY_ENVIRONMENT?: string;
  VITE_APP_RELEASE?: string;
}

const EMAIL = /[\w.+%-]+@[\w-]+(?:\.[\w-]+)+/g;

// Sin PII: ni usuario, ni cookies, ni cabeceras, ni query string (puede llevar tokens); los correos de los mensajes se ocultan.
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  const scrub = (text?: string) => text?.replace(EMAIL, "[email]");

  if (event.message) event.message = scrub(event.message);
  event.exception?.values?.forEach((exception) => {
    exception.value = scrub(exception.value);
  });
  delete event.user;
  if (event.request)
    event.request = event.request.url ? { url: event.request.url.split("?")[0] } : {};
  return event;
}

export function initSentry(env: SentryEnv = import.meta.env): boolean {
  if (env.MODE === "test" || !env.VITE_SENTRY_DSN) return false;

  Sentry.init({
    dsn: env.VITE_SENTRY_DSN,
    environment: env.VITE_SENTRY_ENVIRONMENT || env.MODE,
    release: env.VITE_APP_RELEASE,
    // Sin PII (Sentry 11 sustituye sendDefaultPii por dataCollection): ni usuario, ni cookies, ni cabeceras, ni cuerpos, ni query.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
    },
    beforeSend: scrubEvent,
  });
  return true;
}
