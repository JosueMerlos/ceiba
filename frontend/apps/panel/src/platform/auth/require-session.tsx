import { isApiError, useSessionQuery } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { LoadingState } from "@ceiba/ui";
import { Navigate, Outlet, useLocation } from "react-router";
import { UnexpectedPage } from "../errors/status-pages";
import { loginPathFor } from "./return-path";

/** Gate for private routes: no session (401) goes to login with the return path; any other failure offers a retry. */
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
