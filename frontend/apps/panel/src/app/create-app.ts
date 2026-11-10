import { createApiClient, createCsrfStore } from "@ceiba/api-client";
import { createI18n } from "@ceiba/i18n";
import type { RouteObject } from "react-router";
import { toast } from "@ceiba/ui";
import { describeError, createQueryClient } from "../platform/errors/global-errors";
import { loginPathFor } from "../platform/auth/return-path";
import { createAppRouter, type History } from "./router";

interface CreateAppOptions {
  /** Origen de la API. Vacío = mismo origen (producción y desarrollo detrás del proxy, ADR-0013). */
  apiBaseUrl?: string;
  history?: History;
  /** `false` en pruebas: las consultas fallidas no se reintentan. */
  retry?: false;
  /** Pruebas: reemplaza las páginas dentro del layout (inicio y módulos). */
  workspaceChildren?: RouteObject[];
}

/**
 * Compone todo lo que vive durante la sesión del navegador: i18n, cliente de la API, caché de consultas y router.
 * Una función (no módulos con estado global) para que cada test monte su propio panel aislado.
 */
export async function createApp({
  apiBaseUrl = "",
  history = { type: "browser" },
  retry,
  workspaceChildren,
}: CreateAppOptions = {}) {
  const i18n = await createI18n();
  const apiClient = createApiClient({ baseUrl: apiBaseUrl, csrf: createCsrfStore() });
  const router = createAppRouter(history, workspaceChildren);

  const queryClient = createQueryClient({
    retry,
    onUnauthorized: (fromSession) => {
      const { location } = router.state;
      if (location.pathname === "/login") return;
      // La sesión terminó: nada de lo cacheado debe verlo quien inicie sesión después en este navegador.
      if (!fromSession) queryClient.clear();
      void router.navigate(loginPathFor(location), { replace: true });
    },
    notify: (error) => {
      const message = describeError(error, i18n.t);
      const conflict =
        typeof error === "object" && error !== null && "status" in error && error.status === 409;
      if (conflict) toast.warning(message);
      else toast.error(message);
    },
  });

  return { i18n, apiClient, queryClient, router };
}

export type PanelApp = Awaited<ReturnType<typeof createApp>>;
