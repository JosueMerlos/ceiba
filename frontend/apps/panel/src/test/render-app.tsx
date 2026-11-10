import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { App } from "../app/app";
import { createApp } from "../app/create-app";
import { API } from "./fixtures";

/** Monta el panel COMPLETO (providers, router, API simulada con MSW) en la ruta indicada. */
export async function renderApp({ route = "/" }: { route?: string } = {}) {
  const app = await createApp({
    apiBaseUrl: API,
    history: { type: "memory", initialEntries: [route] },
    retry: false,
  });
  const user = userEvent.setup();
  const view = render(<App app={app} />);
  return { app, user, ...view };
}
