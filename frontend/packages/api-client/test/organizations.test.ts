import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { ApiError, createApiClient, unwrap } from "../src";

// Los cuerpos de los handlers son los que produce la API real (ver specs de rswag del backend).
const BASE = "http://api.test";
const ID = "0198f0a0-0000-7000-8000-000000000001";

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
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

    const body = await unwrap(client.GET("/api/v1/organizations/{id}", { params: { path: { id: ID } } }));

    expect(body.data.id).toBe(ID);
    expect(body.data.name).toBe("Salón Ceiba");
    expect(body.data.legal_name).toBeNull();
    expect(body.data.status).toBe("active");
  });

  test("envía las cookies de sesión (credentials: include)", async () => {
    let credentials: RequestCredentials | undefined;
    server.use(
      http.get(`${BASE}/api/v1/organizations/:id`, ({ request }) => {
        credentials = request.credentials;
        return HttpResponse.json({ data: {} });
      }),
    );

    await client.GET("/api/v1/organizations/{id}", { params: { path: { id: ID } } });

    expect(credentials).toBe("include");
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

    const failure = unwrap(client.GET("/api/v1/organizations/{id}", { params: { path: { id: ID } } }));

    await expect(failure).rejects.toBeInstanceOf(ApiError);
    await expect(failure).rejects.toMatchObject({ status: 404, code: "resource.not_found", requestId: "req-404" });
  });
});
