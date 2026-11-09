import type { components } from "./schema";

/** Un problema `application/problem+json` tal como lo define el contrato (components.schemas.Problem). */
export type Problem = components["schemas"]["Problem"];
/** Error de validación por campo (`errors[]` de un 422). */
export type FieldError = components["schemas"]["FieldError"];

/**
 * Error de la API traducido desde un problem+json (RFC 9457). El frontend decide qué hacer por `status` y `code`
 * (estable y traducible con i18n), nunca por `message`: ver docs/architecture/08-frontend.md ("Errores").
 *
 * Una respuesta HTTP que NO es problem+json (un 502 del proxy, una página HTML) también termina aquí, con
 * `code: "http.<status>"`. Un fallo de red (sin respuesta HTTP) NO: `fetch` rechaza con un `TypeError` que se propaga tal
 * cual; quien captura distingue `isApiError(error)` (el servidor respondió) de un error de red.
 */
export class ApiError extends Error {
  override readonly name = "ApiError";

  constructor(
    readonly status: number,
    readonly code: string,
    readonly title: string,
    readonly errors: FieldError[] = [],
    readonly requestId?: string,
    readonly detail?: string,
    readonly type?: string,
    readonly instance?: string,
  ) {
    super(title);
  }

  /** Construye el error a partir de una respuesta cuyo cuerpo YA se leyó (openapi-fetch lo parsea). */
  static from(response: Response, body: unknown): ApiError {
    if (isProblem(body)) {
      return new ApiError(
        response.status,
        body.code,
        body.title,
        body.errors ?? [],
        body.request_id,
        body.detail,
        body.type,
        body.instance,
      );
    }
    return new ApiError(
      response.status,
      `http.${response.status}`,
      response.statusText || `HTTP ${response.status}`,
    );
  }

  /** Lee el cuerpo de la respuesta (si es JSON) y construye el error. */
  static async fromResponse(response: Response): Promise<ApiError> {
    const body: unknown = await response.json().catch(() => undefined);
    return ApiError.from(response, body);
  }
}

export function isApiError(value: unknown): value is ApiError {
  return value instanceof ApiError;
}

type ProblemBody = Problem & { errors?: FieldError[] };

function isProblem(body: unknown): body is ProblemBody {
  if (typeof body !== "object" || body === null) return false;
  const candidate = body as Record<string, unknown>;
  return typeof candidate.code === "string" && typeof candidate.title === "string";
}
