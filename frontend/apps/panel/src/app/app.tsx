import { ApiClientProvider } from "@ceiba/api-client";
import { I18nextProvider } from "@ceiba/i18n";
import { Toaster } from "@ceiba/ui";
import { QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "react-router";
import type { PanelApp } from "./create-app";

/** Providers del panel: i18n, caché de consultas, cliente de la API, router y avisos. */
export function App({ app }: { app: PanelApp }) {
  return (
    <I18nextProvider i18n={app.i18n}>
      <QueryClientProvider client={app.queryClient}>
        <ApiClientProvider client={app.apiClient}>
          <RouterProvider router={app.router} />
          <Toaster />
        </ApiClientProvider>
      </QueryClientProvider>
    </I18nextProvider>
  );
}
