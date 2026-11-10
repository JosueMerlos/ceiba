import { useMeQuery } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { LoadingState } from "@ceiba/ui";
import { useMemo } from "react";
import { useRoutes } from "react-router";
import { routesFor } from "../../modules/registry";
import { ContextProvider, useContextSelection } from "../context/context-provider";
import { NotFoundPage, UnexpectedPage } from "../errors/status-pages";
import { MeProvider, useMe } from "../me/me-provider";
import { AppShell } from "./app-shell";
import { NoAccessPage } from "./home-page";

/** Private route: loads /me for the chosen context and mounts the layout with what /me allows. */
export function Workspace() {
  return (
    <ContextProvider>
      <MeGate />
    </ContextProvider>
  );
}

function MeGate() {
  const { t } = useTranslation("common");
  const { selection } = useContextSelection();
  const me = useMeQuery(selection);

  if (me.isPending) return <LoadingState label={t("loading")} className="min-h-svh" />;
  if (me.isError) return <UnexpectedPage onRetry={() => void me.refetch()} />;
  // Without an organization there is nothing to show except how to request access.
  if (!me.data.data.context.organization) return <NoAccessPage />;

  return (
    <MeProvider me={me.data.data}>
      <AppShell />
    </MeProvider>
  );
}

/**
 * Routes of active modules (front-end registry). What /me does not offer does not exist: a URL of an inactive module or
 * without permission lands on "not found", as the backend would answer (404, not 403).
 */
export function ModuleRoutes() {
  const me = useMe();
  const routes = useMemo(
    () => [
      ...routesFor(me).map(({ path, element }) => ({ path, element })),
      { path: "*", element: <NotFoundPage /> },
    ],
    [me],
  );
  return useRoutes(routes);
}
