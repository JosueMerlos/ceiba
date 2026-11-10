import { isApiError } from "@ceiba/api-client";
import { translator, type AnyTranslate } from "@ceiba/i18n";
import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";

interface GlobalErrorHandlers {
  /** Sesión vencida: el router lleva al login conservando la ruta. */
  onUnauthorized(): void;
  /** Avisa al usuario (toast) de un fallo que ninguna pantalla va a mostrar. */
  notify(error: unknown): void;
  /** `false` en pruebas: sin reintentos. */
  retry?: false;
}

const isSessionExpired = (error: unknown) =>
  isApiError(error) && error.status === 401 && error.code !== "auth.invalid_credentials";

// Una mutación fallida se avisa al usuario salvo los casos que su formulario ya muestra: 400/422 (validación), 404 y
// el 401 (que lleva al login). 403, 409, 429, 5xx y los fallos de red sí.
const shouldNotify = (error: unknown) =>
  !isApiError(error) || [403, 409, 429].includes(error.status) || error.status >= 500;

/**
 * QueryClient del panel con la política GLOBAL de errores de la API (08-frontend, "Errores"):
 *  - 401 -> login (con ruta de retorno); 403 y 404 de una consulta -> pantalla de permiso / no encontrado;
 *  - 409, 403, 429, 5xx y red en una mutación -> aviso; 422 -> lo muestra el formulario.
 */
export function createQueryClient({ onUnauthorized, notify, retry }: GlobalErrorHandlers) {
  return new QueryClient({
    queryCache: new QueryCache({
      onError: (error) => {
        if (isSessionExpired(error)) onUnauthorized();
      },
    }),
    mutationCache: new MutationCache({
      onError: (error, _variables, _context, mutation) => {
        if (isSessionExpired(error)) return onUnauthorized();
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

/** Mensaje para el usuario. Se decide por `code` (estable y traducible), nunca por el `message` del servidor. */
export function describeError(error: unknown, translate: AnyTranslate): string {
  const t = translator(translate);
  if (!isApiError(error)) return t("errors:network");

  // Clave dinámica (code de la API); `defaultValue` evita el aviso de clave inexistente: aquí la ausencia es normal.
  const byCode = t(`errors:code.${error.code}`, { defaultValue: "" });
  if (byCode) return byCode;
  if (error.status === 403) return t("errors:forbidden.description");
  if (error.status === 404) return t("errors:notFound.description");
  if (error.status === 409) return t("errors:conflict");
  return t("errors:generic");
}
