import { createBrowserRouter, createMemoryRouter, type RouteObject } from "react-router";
import { LoginPage } from "../platform/auth/login-page";
import { RequireSession } from "../platform/auth/require-session";
import { RouteError } from "../platform/errors/status-pages";
import { HomePage } from "../platform/shell/home-page";
import { ModuleRoutes, Workspace } from "../platform/shell/workspace";

export type History = { type: "browser" } | { type: "memory"; initialEntries: string[] };

const pages: RouteObject[] = [
  { index: true, element: <HomePage /> },
  { path: "*", element: <ModuleRoutes /> },
];

function buildRoutes(children: RouteObject[]): RouteObject[] {
  return [
    { path: "/login", element: <LoginPage />, errorElement: <RouteError /> },
    {
      path: "/",
      element: <RequireSession />,
      // A /me or session failure leaves no layout: the only option here is to log out.
      errorElement: <RouteError withLogout />,
      children: [
        {
          element: <Workspace />,
          children: [
            // A PAGE failure (403, 404, error) renders in place and keeps the navigation and selector.
            { errorElement: <RouteError />, children },
          ],
        },
      ],
    },
  ];
}

export function createAppRouter(history: History, children: RouteObject[] = pages) {
  const routes = buildRoutes(children);
  return history.type === "memory"
    ? createMemoryRouter(routes, { initialEntries: history.initialEntries })
    : createBrowserRouter(routes);
}

export type AppRouter = ReturnType<typeof createAppRouter>;
