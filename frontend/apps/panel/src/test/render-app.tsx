import type { RouteObject } from "react-router";
import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { App } from "../app/app";
import { createApp } from "../app/create-app";
import { API } from "./fixtures";

/**
 * Mounts the FULL panel (providers, router, MSW-mocked API) at the given path. Routes load their own i18n namespaces as
 * in production, and a missing key throws.
 */
export async function renderApp({
  route = "/",
  workspaceChildren,
}: { route?: string; workspaceChildren?: RouteObject[] } = {}) {
  const app = await createApp({
    apiBaseUrl: API,
    history: { type: "memory", initialEntries: [route] },
    retry: false,
    workspaceChildren,
    onMissingKey: "throw",
  });
  const user = userEvent.setup();
  const view = render(<App app={app} />);
  return { app, user, ...view };
}
