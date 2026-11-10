import type { components } from "./schema";

/** An `application/problem+json` problem as defined by the contract (components.schemas.Problem). */
export type Problem = components["schemas"]["Problem"];
/** Per-field validation error (`errors[]` of a 422). */
export type FieldError = components["schemas"]["FieldError"];

/**
 * API error translated from a problem+json (RFC 9457). The front end decides what to do by `status` and `code` (stable
 * and translatable with i18n), never by `message`.
 *
 * An HTTP response that is NOT problem+json (a proxy 502, an HTML page) also ends up here, with `code: "http.<status>"`.
 * A network failure (no HTTP response) does NOT: `fetch` rejects with a `TypeError` that propagates as is; callers tell
 * `isApiError(error)` (the server answered) apart from a network error.
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
