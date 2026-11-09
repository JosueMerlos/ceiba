import createClient from "openapi-fetch";
import { ApiError } from "./api-error";
import type { paths } from "./schema";

export interface ApiClientOptions {
  /** Origen de la API. Vacío (por defecto) = mismo origen, que es como corre en producción (ADR-0013). */
  baseUrl?: string;
  /** Para pruebas o entornos sin `fetch` global. */
  fetch?: typeof globalThis.fetch;
}

/**
 * Cliente tipado de la API v1: rutas, parámetros y respuestas salen de backend/openapi/v1.yaml (`pnpm api:generate`).
 * Envía las cookies de sesión (`credentials: "include"`). El token CSRF de las mutaciones llega con M0.07.
 *
 *   const client = createApiClient();
 *   const body = await unwrap(client.GET("/api/v1/organizations/{id}", { params: { path: { id } } }));
 */
export function createApiClient({ baseUrl = "", fetch }: ApiClientOptions = {}) {
  // `fetch` se resuelve en cada llamada (no al crear el cliente): así lo interceptan MSW y los polyfills instalados después.
  const resolveFetch = fetch ?? ((request: Request) => globalThis.fetch(request));
  return createClient<paths>({ baseUrl, credentials: "include", fetch: resolveFetch });
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
