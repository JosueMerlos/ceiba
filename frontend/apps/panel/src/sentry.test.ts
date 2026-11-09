import * as Sentry from "@sentry/react";
import type { ErrorEvent } from "@sentry/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { initSentry, scrubEvent } from "./sentry";

vi.mock("@sentry/react", () => ({ init: vi.fn() }));

afterEach(() => vi.clearAllMocks());

describe("initSentry", () => {
  test("sin DSN no inicializa Sentry (desarrollo local, CI)", () => {
    expect(initSentry({ MODE: "development" })).toBe(false);
    expect(Sentry.init).not.toHaveBeenCalled();
  });

  test("en test queda desactivado aunque exista un DSN", () => {
    expect(initSentry({ MODE: "test", VITE_SENTRY_DSN: "https://k@sentry.example/1" })).toBe(false);
    expect(Sentry.init).not.toHaveBeenCalled();
  });

  test("con DSN inicializa con release y entorno, sin PII y sin trazas ni replays", () => {
    const enabled = initSentry({
      MODE: "production",
      VITE_SENTRY_DSN: "https://k@sentry.example/1",
      VITE_SENTRY_ENVIRONMENT: "staging",
      VITE_APP_RELEASE: "ceiba@abc1234",
    });

    expect(enabled).toBe(true);
    expect(Sentry.init).toHaveBeenCalledWith(
      expect.objectContaining({
        dsn: "https://k@sentry.example/1",
        environment: "staging",
        release: "ceiba@abc1234",
        dataCollection: expect.objectContaining({
          userInfo: false,
          cookies: false,
          httpHeaders: false,
          httpBodies: [],
          urlQueryParams: false,
        }),
        beforeSend: scrubEvent,
      }),
    );
  });

  test("el entorno por defecto es el modo de Vite", () => {
    initSentry({ MODE: "production", VITE_SENTRY_DSN: "https://k@sentry.example/1" });

    expect(Sentry.init).toHaveBeenCalledWith(
      expect.objectContaining({ environment: "production" }),
    );
  });
});

const errorEvent = (partial: Partial<ErrorEvent>) =>
  ({ type: undefined, ...partial }) as ErrorEvent;

describe("scrubEvent", () => {
  test("quita correos de mensajes y excepciones", () => {
    const event = scrubEvent(
      errorEvent({
        message: "falló para ana@ceiba.test",
        exception: { values: [{ type: "Error", value: "no existe otra@ceiba.test" }] },
      }),
    );

    expect(JSON.stringify(event)).not.toMatch(/@ceiba\.test/);
    expect(event.message).toBe("falló para [email]");
  });

  test("descarta usuario, cookies, cabeceras y query string de la request", () => {
    const event = scrubEvent(
      errorEvent({
        user: { email: "ana@ceiba.test", ip_address: "1.2.3.4" },
        request: {
          url: "https://app.example/x?token=abc",
          query_string: "token=abc",
          cookies: { s: "1" },
          headers: { Cookie: "s=1" },
        },
      }),
    );

    expect(event.user).toBeUndefined();
    expect(event.request).toEqual({ url: "https://app.example/x" });
  });
});
