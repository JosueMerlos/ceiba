import { isApiError } from "@ceiba/api-client";
import { translator, type AnyTranslate } from "@ceiba/i18n";
import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";

interface GlobalErrorHandlers {
  /** Expired session: the router goes to login keeping the path. */
  /** `fromSession`: the 401 came from GET /auth/session (nothing to discard and login must not request it again). */
  onUnauthorized(fromSession: boolean): void;
  /** Notifies the user (toast) of a failure no screen will show. */
  notify(error: unknown): void;
  /** `false` in tests: no retries. */
  retry?: false;
}

const isSessionExpired = (error: unknown) =>
  isApiError(error) && error.status === 401 && error.code !== "auth.invalid_credentials";

// A failed mutation notifies the user except for cases the form already shows: 400/422 (validation), 404 and 401
// (which goes to login). 403, 409, 429, 5xx and network failures do notify.
const shouldNotify = (error: unknown) =>
  !isApiError(error) || [403, 409, 429].includes(error.status) || error.status >= 500;

/**
 * Panel QueryClient with the GLOBAL API error policy:
 *  - 401 -> login (with return path); 403 and 404 on a query -> permission / not-found screen;
 *  - 409, 403, 429, 5xx and network on a mutation -> toast; 422 -> shown by the form.
 */
export function createQueryClient({ onUnauthorized, notify, retry }: GlobalErrorHandlers) {
  return new QueryClient({
    queryCache: new QueryCache({
      onError: (error, query) => {
        if (isSessionExpired(error)) onUnauthorized(query.queryKey[0] === "session");
      },
    }),
    mutationCache: new MutationCache({
      onError: (error, _variables, _context, mutation) => {
        if (isSessionExpired(error)) return onUnauthorized(false);
        if (mutation.meta?.silent) return;
        if (shouldNotify(error)) notify(error);
      },
    }),
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        refetchOnWindowFocus: false,
        retry: retry ?? ((count, error) => !(isApiError(error) && error.status < 500) && count < 2),
        throwOnError: (error) =>
          isApiError(error) && (error.status === 403 || error.status === 404),
      },
    },
  });
}

/** User-facing message. Decided by `code` (stable and translatable), never by the server's `message`. */
export function describeError(error: unknown, translate: AnyTranslate): string {
  const t = translator(translate);
  if (!isApiError(error)) return t("errors:network");

  // Dynamic key (API code); `defaultValue` avoids the missing-key warning: absence is normal here.
  const byCode = t(`errors:code.${error.code}`, { defaultValue: "" });
  if (byCode) return byCode;
  if (error.status === 403) return t("errors:forbidden.description");
  if (error.status === 404) return t("errors:notFound.description");
  if (error.status === 409) return t("errors:conflict");
  return t("errors:generic");
}
