import { screen, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import {
  API,
  authSession,
  branch,
  company,
  ids,
  meFixture,
  organization,
  problem,
} from "../test/fixtures";
import { renderApp } from "../test/render-app";
import { respondWith, server, signedInBackend, signedOutBackend } from "../test/server";

const contextButton = () =>
  screen.queryByRole("button", { name: /Cambiar el contexto de trabajo/ });
const mainNav = () => screen.findByRole("navigation", { name: "Navegación principal" });

describe("login", () => {
  it("criterio 1: un usuario con una sola organización, empresa y sucursal entra directo, sin selector", async () => {
    signedOutBackend();
    const { user } = await renderApp({ route: "/login" });
    server.use(
      http.post(`${API}/api/v1/auth/login`, () => HttpResponse.json(authSession("Julia Reyes"))),
    );
    await user.type(
      await screen.findByLabelText("Correo electrónico"),
      "julia@barberia.ceiba.test",
    );
    await user.type(screen.getByLabelText("Contraseña"), "ceiba-demo-2026");
    signedInBackend();

    await user.click(screen.getByRole("button", { name: "Entrar" }));

    const nav = await mainNav();
    expect(within(nav).getByRole("link", { name: "Agenda" })).toBeTruthy();
    expect(contextButton()).toBeNull();
  });

  it("muestra el error de credenciales inválidas, traducido por code, sin salir del formulario", async () => {
    signedOutBackend();
    const { user } = await renderApp({ route: "/login" });
    server.use(
      http.post(
        `${API}/api/v1/auth/login`,
        respondWith(401, problem(401, "auth.invalid_credentials")),
      ),
    );
    await user.type(
      await screen.findByLabelText("Correo electrónico"),
      "julia@barberia.ceiba.test",
    );
    await user.type(screen.getByLabelText("Contraseña"), "incorrecta");

    await user.click(screen.getByRole("button", { name: "Entrar" }));

    expect((await screen.findByRole("alert")).textContent).toBe(
      "El correo o la contraseña no son correctos.",
    );
    expect(screen.getByRole("heading", { name: "Iniciar sesión" })).toBeTruthy();
  });

  it("valida los campos antes de llamar a la API, con mensajes en español asociados al campo", async () => {
    signedOutBackend();
    const { user } = await renderApp({ route: "/login" });

    await user.click(await screen.findByRole("button", { name: "Entrar" }));

    expect(await screen.findByText("Escriba su correo electrónico")).toBeTruthy();
    expect(screen.getByText("Escriba su contraseña")).toBeTruthy();
    expect(screen.getByLabelText("Correo electrónico").getAttribute("aria-invalid")).toBe("true");
  });

  it("criterio 5: tras el login vuelve a la ruta que se había pedido", async () => {
    signedOutBackend();
    const { user, app } = await renderApp({ route: "/agenda" });
    await screen.findByRole("heading", { name: "Iniciar sesión" });
    expect(app.router.state.location.pathname).toBe("/login");
    expect(app.router.state.location.search).toBe("?next=%2Fagenda");
    server.use(http.post(`${API}/api/v1/auth/login`, () => HttpResponse.json(authSession())));
    await user.type(screen.getByLabelText("Correo electrónico"), "julia@barberia.ceiba.test");
    await user.type(screen.getByLabelText("Contraseña"), "ceiba-demo-2026");
    signedInBackend();

    await user.click(screen.getByRole("button", { name: "Entrar" }));

    expect(await screen.findByRole("heading", { name: "Agenda" })).toBeTruthy();
    expect(app.router.state.location.pathname).toBe("/agenda");
  });

  it("un usuario con sesión vigente que abre /login va al panel", async () => {
    signedInBackend();
    const { app } = await renderApp({ route: "/login" });

    await mainNav();

    expect(app.router.state.location.pathname).toBe("/");
  });
});

describe("sesión expirada (criterio 5)", () => {
  it("si la sesión no existe, redirige al login conservando la ruta de retorno", async () => {
    signedOutBackend();
    const { app } = await renderApp({ route: "/agenda?dia=2026-11-09" });

    await screen.findByRole("heading", { name: "Iniciar sesión" });

    expect(app.router.state.location.pathname).toBe("/login");
    expect(new URLSearchParams(app.router.state.location.search).get("next")).toBe(
      "/agenda?dia=2026-11-09",
    );
  });

  it("si CUALQUIER request responde 401 a mitad de uso, redirige y descarta lo cacheado", async () => {
    signedInBackend();
    // La sesión vence mientras se usa: /me responde 401 y, desde ese momento, también la sesión.
    let expired = false;
    server.use(
      http.get(`${API}/api/v1/auth/session`, () =>
        expired
          ? HttpResponse.json(problem(401, "auth.unauthenticated"), { status: 401 })
          : HttpResponse.json(authSession()),
      ),
      http.get(`${API}/api/v1/me`, () => {
        expired = true;
        return HttpResponse.json(problem(401, "auth.unauthenticated"), { status: 401 });
      }),
    );
    const { app } = await renderApp({ route: "/agenda" });

    await screen.findByRole("heading", { name: "Iniciar sesión" });

    expect(new URLSearchParams(app.router.state.location.search).get("next")).toBe("/agenda");
    expect(
      app.queryClient
        .getQueryCache()
        .getAll()
        .filter((query) => query.state.data),
    ).toEqual([]);
  });
});

describe("navegación y módulos", () => {
  it("criterio 3: con appointments inactivo el menú no muestra Agenda y /agenda es «no encontrado»", async () => {
    signedInBackend({ me: meFixture({ modules: [] }) });
    await renderApp({ route: "/agenda" });

    expect(await screen.findByRole("heading", { name: "No encontramos esta página" })).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Agenda" })).toBeNull();
  });

  it("criterio 4: un receptionist solo ve los ítems de navegación cuyos permisos tiene", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist" }) });
    await renderApp();

    const nav = await mainNav();

    expect(within(nav).getByRole("link", { name: "Agenda" })).toBeTruthy();
    expect(within(nav).queryByRole("link", { name: "Resumen de citas" })).toBeNull();
  });

  it("el dueño de la organización ve el resumen y no la agenda", async () => {
    signedInBackend({ me: meFixture({ role: "org_owner", name: "Rosa Mendoza" }) });
    await renderApp();

    const nav = await mainNav();

    expect(within(nav).getByRole("link", { name: "Resumen de citas" })).toBeTruthy();
    expect(within(nav).queryByRole("link", { name: "Agenda" })).toBeNull();
  });

  it("monta la página del módulo (lazy) al navegar y marca el ítem activo", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist" }) });
    const { user } = await renderApp();

    await user.click(within(await mainNav()).getByRole("link", { name: "Agenda" }));

    expect(await screen.findByRole("heading", { name: "Agenda" })).toBeTruthy();
    expect(
      within(await mainNav())
        .getByRole("link", { name: "Agenda" })
        .getAttribute("aria-current"),
    ).toBe("page");
  });

  it("una ruta que no existe muestra «no encontrado» dentro del layout", async () => {
    signedInBackend();
    await renderApp({ route: "/no-existe" });

    expect(await screen.findByRole("heading", { name: "No encontramos esta página" })).toBeTruthy();
    expect(await mainNav()).toBeTruthy();
  });

  it("un receptionist no puede abrir el resumen por URL: lo que /me no ofrece no se monta", async () => {
    signedInBackend({ me: meFixture({ role: "receptionist" }) });
    await renderApp({ route: "/agenda/summary" });

    expect(await screen.findByRole("heading", { name: "No encontramos esta página" })).toBeTruthy();
  });
});

describe("errores de la API", () => {
  it("un 403 al cargar el contexto muestra la pantalla de permiso", async () => {
    signedInBackend();
    server.use(
      http.get(`${API}/api/v1/me`, respondWith(403, problem(403, "access.organization_suspended"))),
    );
    await renderApp();

    expect(
      await screen.findByRole("heading", { name: "No tiene permiso para ver esto" }),
    ).toBeTruthy();
  });

  it("un usuario sin memberships (contexto vacío) ve cómo pedir acceso", async () => {
    signedInBackend({
      me: {
        data: {
          ...meFixture().data,
          context: { organization: null, company: null, branch: null },
          modules: [],
          permissions: [],
          navigation: [],
        },
      },
    });
    await renderApp();

    expect(
      await screen.findByRole("heading", { name: "Todavía no tiene acceso a ninguna empresa" }),
    ).toBeTruthy();
  });
});

describe("selector de contexto", () => {
  const twoOrganizations = () => {
    const orgA = organization(ids.orgA, "Grupo Salud & Estilo");
    const orgB = organization(ids.orgB, "Barbería El Güegüense");
    signedInBackend({
      organizations: [orgA, orgB],
      me: (query) =>
        query.get("organization_id") === ids.orgB
          ? meFixture({
              organization: orgB,
              company: company(ids.companyB, "Barbería Centro"),
              branch: null,
            })
          : meFixture({ organization: orgA, company: company(ids.companyA, "Clínica Sonrisa") }),
    });
  };

  it("criterio 2: con dos organizaciones aparece el selector y cambiar de organización recarga el contexto", async () => {
    twoOrganizations();
    const { user, app } = await renderApp();
    await user.click(await screen.findByRole("button", { name: /Cambiar el contexto de trabajo/ }));

    await user.click(await screen.findByRole("menuitemradio", { name: "Barbería El Güegüense" }));

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: /Cambiar el contexto de trabajo/ }).textContent,
      ).toContain("Barbería Centro"),
    );
    // La caché de la organización anterior ya no está.
    const stale = app.queryClient
      .getQueryCache()
      .findAll({ queryKey: ["me"] })
      .filter(
        (query) =>
          (query.queryKey[1] as { organization_id?: string }).organization_id === undefined,
      );
    expect(stale).toEqual([]);
  });

  it("con varias sucursales ofrece «Todas las sucursales» y cada sucursal", async () => {
    signedInBackend({
      branches: [
        branch(ids.branchA, ids.companyA, "Estilo Centro"),
        branch(ids.branchA2, ids.companyA, "Estilo Altamira"),
      ],
    });
    const { user } = await renderApp();

    await user.click(await screen.findByRole("button", { name: /Cambiar el contexto de trabajo/ }));

    expect(await screen.findByRole("menuitemradio", { name: "Estilo Altamira" })).toBeTruthy();
    expect(screen.getByRole("menuitemradio", { name: "Todas las sucursales" })).toBeTruthy();
  });
});

describe("cuenta", () => {
  /** Tras cerrar la sesión, la API responde 401 a GET /auth/session, como la real. */
  function sessionEndsOn(
    method: "logout" | "sessions",
    record: (request: Request) => void = () => {},
  ) {
    let ended = false;
    server.use(
      http.get(`${API}/api/v1/auth/session`, () =>
        ended
          ? HttpResponse.json(problem(401, "auth.unauthenticated"), { status: 401 })
          : HttpResponse.json(authSession()),
      ),
      http.delete(`${API}/api/v1/auth/${method}`, ({ request }) => {
        ended = true;
        record(request);
        return new HttpResponse(null, { status: 204 });
      }),
    );
  }

  it("cerrar sesión envía el token CSRF y lleva al login", async () => {
    signedInBackend();
    let csrfHeader: string | null = null;
    sessionEndsOn("logout", (request) => {
      csrfHeader = request.headers.get("x-csrf-token");
    });
    const { user } = await renderApp();

    await user.click(await screen.findByRole("button", { name: "Cuenta de Julia Reyes" }));
    await user.click(await screen.findByRole("menuitem", { name: "Cerrar sesión" }));

    expect(await screen.findByRole("heading", { name: "Iniciar sesión" })).toBeTruthy();
    expect(csrfHeader).toBe("csrf-de-prueba");
  });

  it("cerrar todas las sesiones pide confirmación en un diálogo", async () => {
    signedInBackend();
    let called = false;
    sessionEndsOn("sessions", () => {
      called = true;
    });
    const { user } = await renderApp();

    await user.click(await screen.findByRole("button", { name: "Cuenta de Julia Reyes" }));
    await user.click(
      await screen.findByRole("menuitem", { name: "Cerrar sesión en todos los dispositivos" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "¿Cerrar sesión en todos los dispositivos?",
    });
    expect(called).toBe(false);
    await user.click(within(dialog).getByRole("button", { name: "Cerrar todas las sesiones" }));

    expect(await screen.findByRole("heading", { name: "Iniciar sesión" })).toBeTruthy();
    expect(called).toBe(true);
  });
});
