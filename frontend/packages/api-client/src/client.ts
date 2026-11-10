import createClient, { type Middleware } from "openapi-fetch";
import { ApiError } from "./api-error";
import { csrfStore, type CsrfStore } from "./csrf";
import type { paths } from "./schema";

export interface ApiClientOptions {
  /** Origen de la API. Vacío (por defecto) = mismo origen, que es como corre en producción (ADR-0013). */
  baseUrl?: string;
  /** Para pruebas o entornos sin `fetch` global. */
  fetch?: typeof globalThis.fetch;
  /** Dónde vive el token CSRF. Por defecto, el almacén compartido en memoria (`csrfStore`). */
  csrf?: CsrfStore;
}

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);
const SESSION_PATHS = new Set(["/api/v1/auth/login", "/api/v1/auth/session"]);
const SESSION_END_PATHS = new Set(["/api/v1/auth/logout", "/api/v1/auth/sessions"]);

/**
 * Middleware de CSRF: añade `X-CSRF-Token` a toda mutación, captura el token que entregan el login y
 * `GET /auth/session`, y lo olvida al cerrar la sesión o cuando la API responde 401 (sesión vencida).
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
 * Cliente tipado de la API v1: rutas, parámetros y respuestas salen de backend/openapi/v1.yaml (`pnpm api:generate`).
 * Envía las cookies de sesión (`credentials: "include"`). El token CSRF se envía solo en las mutaciones (`csrf.ts`).
 *
 *   const client = createApiClient();
 *   const body = await unwrap(client.GET("/api/v1/organizations/{id}", { params: { path: { id } } }));
 */
export function createApiClient({ baseUrl = "", fetch, csrf = csrfStore }: ApiClientOptions = {}) {
  // `fetch` se resuelve en cada llamada (no al crear el cliente): así lo interceptan MSW y los polyfills instalados después.
  const resolveFetch = fetch ?? ((request: Request) => globalThis.fetch(request));
  const client = createClient<paths>({ baseUrl, credentials: "include", fetch: resolveFetch });
  client.use(csrfMiddleware(csrf));
  return client;
}

export type ApiClient = ReturnType<typeof createApiClient>;

/** Lo que devuelve cualquier llamada de openapi-fetch: o `data` (éxito) o `error` (respuesta no 2xx). */
interface FetchResult {
  data?: unknown;
  error?: unknown;
  response: Response;
}

/**
 * Convierte el resultado `{ data, error }` de openapi-fetch en "devuelve el cuerpo o lanza ApiError". Es lo que usan
 * los `queryFn` de TanStack Query (que esperan una promesa que rechaza ante el fallo). El tipo devuelto es el del
 * cuerpo de éxito declarado en el contrato. (Una respuesta 204 sin cuerpo no la modela: aún no existe ninguna.)
 */
export async function unwrap<TResult extends FetchResult>(
  pending: Promise<TResult>,
): Promise<NonNullable<TResult["data"]>> {
  const result = await pending;
  if (result.error !== undefined) throw ApiError.from(result.response, result.error);
  return result.data as NonNullable<TResult["data"]>;
}
