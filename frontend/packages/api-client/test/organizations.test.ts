import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { ApiError, createApiClient, unwrap } from "../src";

// Handler bodies mirror what the real API produces (see the backend rswag specs).
const BASE = "http://api.test";
const ID = "0198f0a0-0000-7000-8000-000000000001";

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const client = createApiClient({ baseUrl: BASE });

describe("GET /api/v1/organizations/{id}", () => {
  test("tipa y parsea la respuesta", async () => {
    server.use(
      http.get(`${BASE}/api/v1/organizations/:id`, ({ params }) =>
        HttpResponse.json({
          data: {
            id: params.id,
            name: "Salón Ceiba",
            legal_name: null,
            country_code: "NI",
            status: "active",
            created_at: "2026-11-08T20:06:36.003Z",
            updated_at: "2026-11-08T20:06:36.003Z",
          },
        }),
      ),
    );

    const body = await unwrap(
      client.GET("/api/v1/organizations/{id}", { params: { path: { id: ID } } }),
    );

    expect(body.data.id).toBe(ID);
    expect(body.data.name).toBe("Salón Ceiba");
    expect(body.data.legal_name).toBeNull();
    expect(body.data.status).toBe("active");
  });

  test("envía las cookies de sesión (credentials: include)", async () => {
    // MSW normalizes `credentials` when rebuilding the request, so the Request leaving the client is inspected.
    let sent: Request | undefined;
    const spy = async (...args: Parameters<typeof fetch>) => {
      sent = new Request(...args);
      return Response.json({ data: {} });
    };

    await createApiClient({ baseUrl: BASE, fetch: spy }).GET("/api/v1/organizations/{id}", {
      params: { path: { id: ID } },
    });

    expect(sent?.credentials).toBe("include");
  });

  test("un problem+json se convierte en ApiError tipado", async () => {
    server.use(
      http.get(`${BASE}/api/v1/organizations/:id`, () =>
        HttpResponse.json(
          {
            type: "urn:ceiba:error:resource.not_found",
            title: "No se encontró el recurso",
            status: 404,
            code: "resource.not_found",
            instance: `/api/v1/organizations/${ID}`,
            request_id: "req-404",
          },
          { status: 404, headers: { "Content-Type": "application/problem+json" } },
        ),
      ),
    );

    const failure = unwrap(
      client.GET("/api/v1/organizations/{id}", { params: { path: { id: ID } } }),
    );

    await expect(failure).rejects.toBeInstanceOf(ApiError);
    await expect(failure).rejects.toMatchObject({
      status: 404,
      code: "resource.not_found",
      requestId: "req-404",
    });
  });
});
