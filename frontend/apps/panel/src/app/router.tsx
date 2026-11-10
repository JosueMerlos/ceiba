import { createBrowserRouter, createMemoryRouter, type RouteObject } from "react-router";
import { LoginPage } from "../platform/auth/login-page";
import { RequireSession } from "../platform/auth/require-session";
import { RouteError } from "../platform/errors/status-pages";
import { HomePage } from "../platform/shell/home-page";
import { ModuleRoutes, Workspace } from "../platform/shell/workspace";

export type History = { type: "browser" } | { type: "memory"; initialEntries: string[] };

const routes: RouteObject[] = [
  { path: "/login", element: <LoginPage />, errorElement: <RouteError /> },
  {
    path: "/",
    element: <RequireSession />,
    errorElement: <RouteError />,
    children: [
      {
        element: <Workspace />,
        children: [
          { index: true, element: <HomePage /> },
          // Las rutas de los módulos activos se resuelven en ModuleRoutes con lo que dice /me.
          { path: "*", element: <ModuleRoutes /> },
        ],
      },
    ],
  },
];

export function createAppRouter(history: History) {
  return history.type === "memory"
    ? createMemoryRouter(routes, { initialEntries: history.initialEntries })
    : createBrowserRouter(routes);
}

export type AppRouter = ReturnType<typeof createAppRouter>;
