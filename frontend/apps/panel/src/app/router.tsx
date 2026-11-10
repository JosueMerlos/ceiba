import { createBrowserRouter, createMemoryRouter, type RouteObject } from "react-router";
import { LoginPage } from "../platform/auth/login-page";
import { RequireSession } from "../platform/auth/require-session";
import { RouteError } from "../platform/errors/status-pages";
import { HomePage } from "../platform/shell/home-page";
import { ModuleRoutes, Workspace } from "../platform/shell/workspace";

export type History = { type: "browser" } | { type: "memory"; initialEntries: string[] };

// Páginas dentro del layout. Las rutas de los módulos activos se resuelven en ModuleRoutes con lo que dice /me.
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
      // Un fallo de /me o de la sesión no deja layout: aquí solo cabe salir (cerrar sesión).
      errorElement: <RouteError withLogout />,
      children: [
        {
          element: <Workspace />,
          children: [
            // Un fallo de una PÁGINA (403, 404, error) se muestra en su lugar y deja la navegación y el selector.
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
