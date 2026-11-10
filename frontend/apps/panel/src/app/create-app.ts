import { createApiClient, createCsrfStore } from "@ceiba/api-client";
import { createI18n } from "@ceiba/i18n";
import type { RouteObject } from "react-router";
import { toast } from "@ceiba/ui";
import { describeError, createQueryClient } from "../platform/errors/global-errors";
import { loginPathFor } from "../platform/auth/return-path";
import { createAppRouter, type History } from "./router";

interface CreateAppOptions {
  /** API origin. Empty = same origin (production, and development behind the proxy). */
  apiBaseUrl?: string;
  history?: History;
  /** `false` in tests: failed queries are not retried. */
  retry?: false;
  /** Tests: replaces the pages inside the layout (home and modules). */
  workspaceChildren?: RouteObject[];
}

/**
 * Composes everything that lives for the browser session: i18n, API client, query cache and router.
 * A function (not global-state modules) so each test mounts its own isolated panel.
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
      // The session ended: nothing cached may be seen by whoever logs in next in this browser.
      if (!fromSession) queryClient.clear();
      // A 401 from the session itself is a cold deep link; any other 401 is a session that expired during use.
      void router.navigate(loginPathFor(location, { expired: !fromSession }), { replace: true });
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
