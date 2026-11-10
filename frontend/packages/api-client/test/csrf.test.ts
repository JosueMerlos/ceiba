import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test } from "vitest";
import { createApiClient, createCsrfStore } from "../src";

const BASE = "http://api.test";
const session = (token: string) => ({
  data: {
    user: { id: "0198f0a0-0000-7000-8000-000000000001", email: "rosa@x.test", full_name: "Rosa" },
    csrf_token: token,
    expires_at: "2026-11-10T00:00:00Z",
  },
});

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

let csrf = createCsrfStore();
beforeEach(() => {
  csrf = createCsrfStore();
});

/** Registra un handler que anota las cabeceras que llegaron. */
function record(
  method: "get" | "post" | "delete",
  path: string,
  body: Record<string, unknown> | null = {},
  status = 200,
) {
  const seen: Headers[] = [];
  server.use(
    http[method](`${BASE}${path}`, ({ request }) => {
      seen.push(request.headers);
      return status === 204
        ? new HttpResponse(null, { status })
        : HttpResponse.json(body, { status });
    }),
  );
  return seen;
}

describe("token CSRF (07-api-contract, 11-security)", () => {
  test("lo guarda en memoria al iniciar sesión y lo envía en la mutación siguiente", async () => {
    const client = createApiClient({ baseUrl: BASE, csrf });
    record("post", "/api/v1/auth/login", session("token-del-login"));
    const logout = record("delete", "/api/v1/auth/logout", null, 204);

    await client.POST("/api/v1/auth/login", { body: { email: "rosa@x.test", password: "x" } });
    expect(csrf.get()).toBe("token-del-login");
    await client.DELETE("/api/v1/auth/logout", { params: { header: { "X-CSRF-Token": "" } } });

    expect(logout[0]?.get("x-csrf-token")).toBe("token-del-login");
  });

  test("lo recupera con GET /auth/session al arrancar (recarga de la página)", async () => {
    const client = createApiClient({ baseUrl: BASE, csrf });
    record("get", "/api/v1/auth/session", session("token-recuperado"));

    await client.GET("/api/v1/auth/session");

    expect(csrf.get()).toBe("token-recuperado");
  });

  test("las lecturas no llevan el token", async () => {
    const client = createApiClient({ baseUrl: BASE, csrf });
    csrf.set("abc");
    const seen = record("get", "/api/v1/me", { data: {} });

    await client.GET("/api/v1/me");

    expect(seen[0]?.has("x-csrf-token")).toBe(false);
  });

  test("se limpia al cerrar la sesión", async () => {
    const client = createApiClient({ baseUrl: BASE, csrf });
    csrf.set("abc");
    record("delete", "/api/v1/auth/logout", null, 204);

    await client.DELETE("/api/v1/auth/logout", { params: { header: { "X-CSRF-Token": "" } } });

    expect(csrf.get()).toBeUndefined();
  });

  test("un login fallido no deja un token a medias", async () => {
    const client = createApiClient({ baseUrl: BASE, csrf });
    record(
      "post",
      "/api/v1/auth/login",
      { type: "urn:x", title: "x", status: 401, code: "auth.invalid_credentials" },
      401,
    );

    await client.POST("/api/v1/auth/login", { body: { email: "a@b.test", password: "mala" } });

    expect(csrf.get()).toBeUndefined();
  });
});
