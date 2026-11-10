import { isApiError, useSessionQuery } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { LoadingState } from "@ceiba/ui";
import { Navigate, Outlet, useLocation } from "react-router";
import { UnexpectedPage } from "../errors/status-pages";
import { loginPathFor } from "./return-path";

/** Puerta de las rutas privadas: sin sesión (401) va al login con la ruta de retorno; otro fallo ofrece reintentar. */
export function RequireSession() {
  const { t } = useTranslation("common");
  const location = useLocation();
  const session = useSessionQuery();

  if (session.isPending) return <LoadingState label={t("loading")} className="min-h-svh" />;
  if (session.isError) {
    if (isApiError(session.error) && session.error.status === 401) {
      return <Navigate to={loginPathFor(location)} replace />;
    }
    return <UnexpectedPage onRetry={() => void session.refetch()} />;
  }
  return <Outlet />;
}
