import { screen, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { branch, ids, meFixture, problem, validationProblem } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { server, signedInBackend } from "../../test/server";
import { CUSTOMER_PERMISSIONS, customerFixture, customersUrl } from "./test-support";

const page = (data: unknown[], hasMore = false) => ({
  data,
  page: { has_more: hasMore, next_cursor: hasMore ? "siguiente" : null },
});

const receptionist = (extra: string[] = CUSTOMER_PERMISSIONS) =>
  signedInBackend({ me: meFixture({ role: "receptionist", extraPermissions: extra }) });

describe("lista de clientes", () => {
  it("quien lee clientes ve el ítem Clientes en el menú y la lista con nombre, teléfono y correo", async () => {
    receptionist();
    server.use(
      http.get(customersUrl(), () =>
        HttpResponse.json(
          page([customerFixture({ full_name: "Fernanda Ruiz", email: "fer@correo.com" })]),
        ),
      ),
    );
    await renderApp({ route: "/customers" });

    const row = await screen.findByRole("row", { name: /Fernanda Ruiz/ });
    expect(within(row).getAllByText("+505 8812 3456").length).toBeGreaterThan(0);
    expect(within(row).getByText("fer@correo.com")).toBeTruthy();
    const nav = screen.getByRole("navigation", { name: "Navegación principal" });
    expect(within(nav).getByRole("link", { name: "Clientes" }).getAttribute("href")).toBe(
      "/customers",
    );
  });

  it("la búsqueda pide por teléfono si se escriben dígitos y por nombre si se escriben letras", async () => {
    receptionist();
    const queries: string[] = [];
    server.use(
      http.get(customersUrl(), ({ request }) => {
        queries.push(new URL(request.url).search);
        return HttpResponse.json(page([]));
      }),
    );
    const { user } = await renderApp({ route: "/customers" });
    const search = await screen.findByRole("searchbox", { name: "Buscar clientes" });

    await user.type(search, "8812");
    await screen.findByText("Ningún cliente coincide con «8812»");
    await user.clear(search);
    await user.type(search, "Fer");
    await screen.findByText("Ningún cliente coincide con «Fer»");

    expect(queries.some((query) => query.includes("phone=8812"))).toBe(true);
    expect(queries.some((query) => query.includes("name_prefix=Fer"))).toBe(true);
  });

  it("crea un cliente en el modal, en un solo paso, y abre su ficha", async () => {
    receptionist();
    let body: unknown;
    server.use(
      http.get(customersUrl(), () => HttpResponse.json(page([]))),
      http.post(customersUrl(), async ({ request }) => {
        body = await request.json();
        return HttpResponse.json(
          { data: customerFixture({ full_name: "Ana Pérez" }) },
          { status: 201 },
        );
      }),
      http.get(`${customersUrl()}/:id`, () =>
        HttpResponse.json({ data: customerFixture({ full_name: "Ana Pérez" }) }),
      ),
    );
    const { user } = await renderApp({ route: "/customers" });

    await user.click(await screen.findByRole("button", { name: "Nuevo cliente" }));
    const dialog = await screen.findByRole("dialog", { name: "Nuevo cliente" });
    expect(within(dialog).queryByRole("list", { name: "Pasos" })).toBeNull();
    await user.type(within(dialog).getByLabelText("Nombre completo"), "Ana Pérez");
    await user.type(within(dialog).getByLabelText("Teléfono"), "8812 3456");
    await user.type(within(dialog).getByLabelText("Correo"), "ana@correo.com");
    await user.click(within(dialog).getByRole("button", { name: "Guardar cliente" }));

    expect(await screen.findByRole("heading", { level: 1, name: "Ana Pérez" })).toBeTruthy();
    expect(body).toEqual({
      full_name: "Ana Pérez",
      phone_e164: "8812 3456",
      email: "ana@correo.com",
      notes: null,
    });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("con «Todas las sucursales» y varias pide elegir una en el selector global, sin lista", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        extraPermissions: CUSTOMER_PERMISSIONS,
        branch: null,
      }),
      branches: [
        branch(ids.branchA, ids.companyA, "Sucursal Centro"),
        branch(ids.branchA2, ids.companyA, "Sucursal Norte"),
      ],
    });
    await renderApp({ route: "/customers" });

    expect(await screen.findByRole("heading", { name: "Elija una sucursal" })).toBeTruthy();
    expect(screen.queryByRole("searchbox", { name: "Buscar clientes" })).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
    expect(screen.queryByRole("button", { name: "Nuevo cliente" })).toBeNull();
  });

  it("un teléfono repetido al crear se muestra junto al campo, sin cerrar el modal", async () => {
    receptionist();
    server.use(
      http.get(customersUrl(), () => HttpResponse.json(page([]))),
      http.post(customersUrl(), () =>
        HttpResponse.json(validationProblem("phone_e164", "taken", "ya pertenece a otro cliente"), {
          status: 422,
        }),
      ),
    );
    const { user } = await renderApp({ route: "/customers" });

    await user.click(await screen.findByRole("button", { name: "Nuevo cliente" }));
    const dialog = await screen.findByRole("dialog", { name: "Nuevo cliente" });
    await user.type(within(dialog).getByLabelText("Nombre completo"), "Ana Pérez");
    await user.type(within(dialog).getByLabelText("Teléfono"), "8812 3456");
    await user.click(within(dialog).getByRole("button", { name: "Guardar cliente" }));

    expect(await within(dialog).findByText("ya pertenece a otro cliente")).toBeTruthy();
    expect(screen.getByRole("dialog", { name: "Nuevo cliente" })).toBeTruthy();
  });

  it("sin clientes invita a crear el primero o a importarlos", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        extraPermissions: [...CUSTOMER_PERMISSIONS, "platform.customer.import"],
      }),
    });
    server.use(http.get(customersUrl(), () => HttpResponse.json(page([]))));
    await renderApp({ route: "/customers" });

    expect(await screen.findByRole("heading", { name: "Todavía no hay clientes" })).toBeTruthy();
    expect(
      screen.getAllByRole("link", { name: "Importar desde CSV" })[0]!.getAttribute("href"),
    ).toBe("/customers/import");
  });

  it("si la lista falla ofrece reintentar", async () => {
    receptionist();
    server.use(
      http.get(customersUrl(), () => HttpResponse.json(problem(500, "internal"), { status: 500 })),
    );
    await renderApp({ route: "/customers" });

    expect(await screen.findByRole("button", { name: "Reintentar" })).toBeTruthy();
  });

  it("sin permiso para leer clientes la pantalla no se muestra", async () => {
    receptionist([]);
    await renderApp({ route: "/customers" });

    expect(
      await screen.findByRole("heading", { name: "No tiene permiso para ver esto" }),
    ).toBeTruthy();
  });
});
