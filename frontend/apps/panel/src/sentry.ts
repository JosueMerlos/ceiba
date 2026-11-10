import * as Sentry from "@sentry/react";
import type { ErrorEvent } from "@sentry/react";

// Vite variables (set at build time). Without VITE_SENTRY_DSN Sentry stays inactive; in `test` mode too.
//   VITE_SENTRY_DSN          panel project DSN
//   VITE_SENTRY_ENVIRONMENT  Sentry environment (defaults to the Vite mode)
//   VITE_APP_RELEASE         deploy identifier (the same SHA as the backend's APP_RELEASE)
export interface SentryEnv {
  MODE: string;
  VITE_SENTRY_DSN?: string;
  VITE_SENTRY_ENVIRONMENT?: string;
  VITE_APP_RELEASE?: string;
}

const EMAIL = /[\w.+%-]+@[\w-]+(?:\.[\w-]+)+/g;

// No PII: no user, cookies, headers or query string (it may carry tokens); emails in messages are masked.
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
    // No PII (Sentry 11 replaces sendDefaultPii with dataCollection): no user, cookies, headers, bodies or query.
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
