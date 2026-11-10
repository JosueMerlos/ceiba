// @vitest-environment jsdom
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import type { ReactNode } from "react";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  ApiClientProvider,
  ApiError,
  createApiClient,
  createCsrfStore,
  queryKeys,
  useLoginMutation,
  useMeQuery,
  useSessionQuery,
} from "../src";

const BASE = "http://api.test";
const user = { id: "0198f0a0-0000-7000-8000-000000000001", email: "rosa@x.test", full_name: "Rosa" };
const authSession = {
  data: { user, csrf_token: "tok", expires_at: "2026-11-10T00:00:00Z" },
};

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function setup() {
  const csrf = createCsrfStore();
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const client = createApiClient({ baseUrl: BASE, csrf });
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      <ApiClientProvider client={client}>{children}</ApiClientProvider>
    </QueryClientProvider>
  );
  return { csrf, queryClient, wrapper };
}

describe("hooks base de TanStack Query", () => {
  test("useSessionQuery devuelve la sesión y deja el token CSRF listo", async () => {
    const { wrapper, csrf } = setup();
    server.use(http.get(`${BASE}/api/v1/auth/session`, () => HttpResponse.json(authSession)));

    const { result } = renderHook(() => useSessionQuery(), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.data.user.full_name).toBe("Rosa");
    expect(csrf.get()).toBe("tok");
  });

  test("un 401 rechaza con ApiError tipado (la UI decide por code)", async () => {
    const { wrapper } = setup();
    server.use(
      http.get(`${BASE}/api/v1/auth/session`, () =>
        HttpResponse.json(
          { type: "urn:x", title: "Sin sesión", status: 401, code: "auth.unauthenticated" },
          { status: 401 },
        ),
      ),
    );

    const { result } = renderHook(() => useSessionQuery(), { wrapper });

    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.error).toBeInstanceOf(ApiError);
    expect((result.current.error as ApiError).code).toBe("auth.unauthenticated");
  });

  test("useMeQuery envía el contexto elegido como parámetros y lo incluye en la clave", async () => {
    const { wrapper, queryClient } = setup();
    let query = "";
    server.use(
      http.get(`${BASE}/api/v1/me`, ({ request }) => {
        query = new URL(request.url).search;
        return HttpResponse.json({ data: { principal: { id: "1", name: "R", email: "r@x" } } });
      }),
    );
    const context = { organization_id: "org-1", company_id: "co-1" };

    const { result } = renderHook(() => useMeQuery(context), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(query).toBe("?organization_id=org-1&company_id=co-1");
    expect(queryClient.getQueryData(queryKeys.me(context))).toBeTruthy();
    expect(queryKeys.me(context)).not.toEqual(queryKeys.me({ organization_id: "org-2" }));
  });

  test("useLoginMutation guarda la sesión en la caché y el token CSRF", async () => {
    const { wrapper, queryClient, csrf } = setup();
    server.use(http.post(`${BASE}/api/v1/auth/login`, () => HttpResponse.json(authSession)));

    const { result } = renderHook(() => useLoginMutation(), { wrapper });
    await act(() => result.current.mutateAsync({ email: "rosa@x.test", password: "ceiba" }));

    expect(csrf.get()).toBe("tok");
    expect(queryClient.getQueryData(queryKeys.session)).toEqual(authSession);
  });

  test("useLoginMutation rechaza con ApiError ante credenciales inválidas", async () => {
    const { wrapper } = setup();
    server.use(
      http.post(`${BASE}/api/v1/auth/login`, () =>
        HttpResponse.json(
          { type: "urn:x", title: "Inválidas", status: 401, code: "auth.invalid_credentials" },
          { status: 401 },
        ),
      ),
    );

    const { result } = renderHook(() => useLoginMutation(), { wrapper });

    await expect(
      act(() => result.current.mutateAsync({ email: "a@b.test", password: "x" })),
    ).rejects.toMatchObject({ status: 401, code: "auth.invalid_credentials" });
  });
});
