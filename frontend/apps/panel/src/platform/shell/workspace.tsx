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

/** Ruta privada: carga /me para el contexto elegido y monta el layout con lo que /me permite. */
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
  // Sin organización no hay nada que mostrar salvo cómo pedir acceso.
  if (!me.data.data.context.organization) return <NoAccessPage />;

  return (
    <MeProvider me={me.data.data}>
      <AppShell />
    </MeProvider>
  );
}

/**
 * Rutas de los módulos activos (registro del front). Lo que /me no ofrece no existe: una URL de un módulo inactivo o
 * sin permiso cae en «no encontrado», igual que respondería el backend (404, no 403).
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
