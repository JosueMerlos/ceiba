import createClient, { type Middleware } from "openapi-fetch";
import { ApiError } from "./api-error";
import { csrfStore, type CsrfStore } from "./csrf";
import type { paths } from "./schema";

export interface ApiClientOptions {
  /** API origin. Empty (default) = same origin, which is how it runs in production. */
  baseUrl?: string;
  /** For tests or environments without a global `fetch`. */
  fetch?: typeof globalThis.fetch;
  /** Where the CSRF token lives. Defaults to the shared in-memory store (`csrfStore`). */
  csrf?: CsrfStore;
}

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);
const SESSION_PATHS = new Set(["/api/v1/auth/login", "/api/v1/auth/session"]);
const SESSION_END_PATHS = new Set(["/api/v1/auth/logout", "/api/v1/auth/sessions"]);

/**
 * CSRF middleware: adds `X-CSRF-Token` to every mutation, captures the token that login and `GET /auth/session`
 * deliver, and forgets it on logout or when the API answers 401 (expired session).
 */
function csrfMiddleware(csrf: CsrfStore): Middleware {
  return {
    onRequest({ request }) {
      const token = csrf.get();
      if (token && !SAFE_METHODS.has(request.method)) request.headers.set("X-CSRF-Token", token);
      return request;
    },
    async onResponse({ response, schemaPath }) {
      const isSessionEnd = SESSION_END_PATHS.has(schemaPath);
      if (response.ok && SESSION_PATHS.has(schemaPath)) {
        const body: unknown = await response
          .clone()
          .json()
          .catch(() => undefined);
        const token = (body as { data?: { csrf_token?: unknown } } | undefined)?.data?.csrf_token;
        if (typeof token === "string") csrf.set(token);
      } else if (
        (response.ok && isSessionEnd) ||
        (response.status === 401 && schemaPath !== "/api/v1/auth/login")
      ) {
        csrf.clear();
      }
      return response;
    },
  };
}

/**
 * Typed API v1 client: routes, parameters and responses come from backend/openapi/v1.yaml (`pnpm api:generate`).
 * Sends the session cookies (`credentials: "include"`). The CSRF token is sent only on mutations (`csrf.ts`).
 *
 *   const client = createApiClient();
 *   const body = await unwrap(client.GET("/api/v1/organizations/{id}", { params: { path: { id } } }));
 */
export function createApiClient({ baseUrl = "", fetch, csrf = csrfStore }: ApiClientOptions = {}) {
  // `fetch` is resolved on every call (not when the client is created) so MSW and later-installed polyfills intercept it.
  const resolveFetch = fetch ?? ((request: Request) => globalThis.fetch(request));
  const client = createClient<paths>({ baseUrl, credentials: "include", fetch: resolveFetch });
  client.use(csrfMiddleware(csrf));
  return client;
}

export type ApiClient = ReturnType<typeof createApiClient>;

/** What any openapi-fetch call returns: either `data` (success) or `error` (non-2xx response). */
interface FetchResult {
  data?: unknown;
  error?: unknown;
  response: Response;
}

/**
 * Turns openapi-fetch's `{ data, error }` result into "return the body or throw ApiError", which is what TanStack Query
 * `queryFn`s need (a promise that rejects on failure). The return type is the success body declared in the contract.
 * (A bodiless 204 is not modeled: none exists yet.)
 */
export async function unwrap<TResult extends FetchResult>(
  pending: Promise<TResult>,
): Promise<NonNullable<TResult["data"]>> {
  const result = await pending;
  if (result.error !== undefined) throw ApiError.from(result.response, result.error);
  return result.data as NonNullable<TResult["data"]>;
}
