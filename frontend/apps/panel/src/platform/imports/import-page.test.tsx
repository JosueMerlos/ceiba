import type { components } from "@ceiba/api-client";
import { screen, within } from "@testing-library/react";
import { delay, http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, branch, ids, meFixture, problem } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { server, signedInBackend } from "../../test/server";

type Batch = components["schemas"]["ImportBatch"];

const ROUTE = "/customers/import";
const IMPORTS = `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}/branches/${ids.branchA}/imports`;
const batchId = "0198f0a0-0000-7000-8000-00000000b001";
const IMPORT_PERMISSIONS = ["platform.customer.read", "platform.customer.import"];

const batch = (overrides: Partial<Batch> = {}): { data: Batch } => ({
  data: {
    id: batchId,
    kind: "customers",
    status: "previewed",
    duplicate_mode: null,
    duplicate_modes: ["skip", "update"],
    columns: ["nombre", "telefono", "correo", "notas"],
    required_columns: ["nombre", "telefono"],
    warnings: [],
    total_count: 100,
    ready_count: 97,
    rejected_count: 3,
    created_count: 0,
    updated_count: 0,
    restored_count: 0,
    skipped_count: 0,
    failed_count: 0,
    expires_at: "2026-11-24T12:00:00.000Z",
    confirmed_at: null,
    finished_at: null,
    created_at: "2026-11-23T12:00:00.000Z",
    preview: [
      {
        row_number: 2,
        status: "ready",
        error_codes: {},
        values: { nombre: "Ana Pérez", telefono: "8888 7777", correo: null },
      },
      {
        row_number: 3,
        status: "rejected",
        error_codes: { telefono: "invalid" },
        values: { nombre: "Luis", telefono: "123", correo: null },
      },
    ],
    ...overrides,
  },
});

const rejectedRows = {
  data: [
    { row_number: 3, status: "rejected", error_codes: { telefono: "invalid" }, values: null },
    { row_number: 40, status: "rejected", error_codes: { nombre: "blank" }, values: null },
    {
      row_number: 77,
      status: "rejected",
      error_codes: { telefono: "duplicate_in_file" },
      values: null,
    },
  ],
  page: { has_more: false, next_cursor: null },
};

const manager = (extra = IMPORT_PERMISSIONS, modules = ["appointments"]) =>
  signedInBackend({ me: meFixture({ role: "company_manager", modules, extraPermissions: extra }) });

const csv = (text = "nombre;telefono\nAna Pérez;8888 7777\n") =>
  new File([text], "clientes.csv", { type: "text/csv" });

async function uploadCustomers(file = csv()) {
  const view = await renderApp({ route: ROUTE });
  await view.user.click(await screen.findByRole("radio", { name: "Clientes" }));
  await view.user.upload(screen.getByLabelText("Archivo CSV"), file);
  return view;
}

describe("importación desde CSV", () => {
  it("sube el archivo en base64, resume la previsualización y lista cada fila con error y su motivo", async () => {
    manager();
    let sent: unknown;
    server.use(
      http.post(IMPORTS, async ({ request }) => {
        sent = await request.json();
        return HttpResponse.json(batch({ warnings: ["consent_not_recorded"] }), { status: 201 });
      }),
      http.get(`${IMPORTS}/${batchId}/rows`, () => HttpResponse.json(rejectedRows)),
    );
    await uploadCustomers();

    const summary = await screen.findByRole("region", { name: "Resumen del archivo" });
    expect(within(summary).getByText("97 listas para importar")).toBeTruthy();
    expect(within(summary).getByText("3 con errores: no se importarán")).toBeTruthy();
    expect(screen.getByText(/no se registra el consentimiento/i)).toBeTruthy();
    const errors = await screen.findByRole("list", { name: "Filas con errores" });
    expect(
      within(errors)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual([
      "Fila 3: Teléfono: no es un número válido",
      "Fila 40: Nombre: está vacío",
      "Fila 77: Teléfono: se repite en el archivo",
    ]);
    expect(sent).toEqual({
      kind: "customers",
      content_base64: btoa("nombre;telefono\nAna PÃ©rez;8888 7777\n"),
    });
  });

  it("confirma con «actualizar» y, al terminar, muestra cuántos se crearon, actualizaron y omitieron", async () => {
    manager();
    let confirmed: unknown;
    let polls = 0;
    server.use(
      http.post(IMPORTS, () => HttpResponse.json(batch(), { status: 201 })),
      http.get(`${IMPORTS}/${batchId}/rows`, () => HttpResponse.json(rejectedRows)),
      http.post(`${IMPORTS}/${batchId}/confirm`, async ({ request }) => {
        confirmed = await request.json();
        return HttpResponse.json(batch({ status: "queued", duplicate_mode: "update" }), {
          status: 202,
        });
      }),
      http.get(`${IMPORTS}/${batchId}`, () => {
        polls += 1;
        return HttpResponse.json(
          polls < 2
            ? batch({ status: "processing", created_count: 40 })
            : batch({
                status: "completed",
                created_count: 90,
                updated_count: 5,
                skipped_count: 2,
                ready_count: 0,
              }),
        );
      }),
    );
    const { user } = await uploadCustomers();

    await user.click(await screen.findByRole("radio", { name: /Actualizar los que ya existen/ }));
    await user.click(screen.getByRole("button", { name: "Importar 97 filas" }));

    const report = await screen.findByRole(
      "region",
      { name: "Importación terminada" },
      { timeout: 5000 },
    );
    expect(within(report).getByText("90 creados")).toBeTruthy();
    expect(within(report).getByText("5 actualizados")).toBeTruthy();
    expect(within(report).getByText("2 omitidos")).toBeTruthy();
    expect(confirmed).toEqual({ duplicate_mode: "update" });
  });

  it("las filas con error se pueden ver todas, página a página", async () => {
    manager();
    server.use(
      http.post(IMPORTS, () => HttpResponse.json(batch({ rejected_count: 101 }), { status: 201 })),
      http.get(`${IMPORTS}/${batchId}/rows`, ({ request }) => {
        const after = new URL(request.url).searchParams.get("after");
        const rows = after
          ? [
              {
                row_number: 300,
                status: "rejected",
                error_codes: { nombre: "blank" },
                values: null,
              },
            ]
          : Array.from({ length: 100 }, (_, index) => ({
              row_number: index + 2,
              status: "rejected",
              error_codes: { telefono: "invalid" },
              values: null,
            }));
        return HttpResponse.json({
          data: rows,
          page: { has_more: !after, next_cursor: after ? null : "siguiente" },
        });
      }),
    );
    const { user } = await uploadCustomers();

    const errors = await screen.findByRole("list", { name: "Filas con errores" });
    expect(within(errors).getAllByRole("listitem")).toHaveLength(100);
    await user.click(screen.getByRole("button", { name: "Ver más filas con errores" }));

    expect(await within(errors).findByText("Fila 300: Nombre: está vacío")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Ver más filas con errores" })).toBeNull();
  });

  it("el reporte final lista las filas que no se pudieron importar y por qué", async () => {
    manager();
    server.use(
      http.post(IMPORTS, () => HttpResponse.json(batch({ rejected_count: 0 }), { status: 201 })),
      http.post(`${IMPORTS}/${batchId}/confirm`, () =>
        HttpResponse.json(batch({ status: "queued", duplicate_mode: "skip" }), { status: 202 }),
      ),
      http.get(`${IMPORTS}/${batchId}`, () =>
        HttpResponse.json(
          batch({
            status: "completed",
            created_count: 95,
            failed_count: 2,
            ready_count: 0,
            rejected_count: 0,
          }),
        ),
      ),
      http.get(`${IMPORTS}/${batchId}/rows`, ({ request }) =>
        HttpResponse.json({
          data:
            new URL(request.url).searchParams.get("status") === "failed"
              ? [
                  {
                    row_number: 9,
                    status: "failed",
                    error_codes: { base: "timeout" },
                    values: null,
                  },
                  {
                    row_number: 31,
                    status: "failed",
                    error_codes: { telefono: "taken" },
                    values: null,
                  },
                ]
              : [],
          page: { has_more: false, next_cursor: null },
        }),
      ),
    );
    const { user } = await uploadCustomers();

    await user.click(await screen.findByRole("button", { name: "Importar 97 filas" }));

    const failed = await screen.findByRole(
      "list",
      { name: "Filas que no se importaron" },
      { timeout: 5000 },
    );
    expect(
      within(failed)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual([
      "Fila 9: no se aplicó: la importación se interrumpió",
      "Fila 31: Teléfono: ya existe",
    ]);
  });

  it("mientras sube el archivo no se puede cambiar de tipo: la previsualización sería de otro", async () => {
    manager();
    server.use(
      http.post(IMPORTS, async () => {
        await delay("infinite");
        return HttpResponse.json(batch(), { status: 201 });
      }),
    );
    await uploadCustomers();

    expect(await screen.findByText("Revisando el archivo…")).toBeTruthy();
    expect((screen.getByRole("radio", { name: "Clientes" }) as HTMLInputElement).disabled).toBe(
      true,
    );
  });

  it("un archivo de más de 5000 filas muestra el mensaje del servidor", async () => {
    manager();
    server.use(
      http.post(IMPORTS, () =>
        HttpResponse.json(
          {
            ...problem(422, "import.too_many_rows"),
            detail: "El archivo tiene 6000 filas y el máximo es 5000: divídelo en varios archivos",
          },
          { status: 422 },
        ),
      ),
    );
    await uploadCustomers();

    expect(
      await screen.findByText(
        "El archivo tiene 6000 filas y el máximo es 5000: divídelo en varios archivos",
      ),
    ).toBeTruthy();
  });

  it("ofrece solo los tipos que el rol puede importar, cada uno con su plantilla", async () => {
    manager([...IMPORT_PERMISSIONS], []);
    await renderApp({ route: ROUTE });

    const kinds = await screen.findByRole("radiogroup", { name: "Qué va a importar" });
    expect(within(kinds).getAllByRole("radio")).toHaveLength(1);
    expect(within(kinds).getByRole("radio", { name: "Clientes" })).toBeTruthy();
    expect(
      screen.getByRole("link", { name: "Descargar la plantilla de clientes" }).getAttribute("href"),
    ).toBe("/import-templates/clientes.csv");
  });

  it("con «Todas las sucursales» y varias pide elegir una en el selector global antes de subir nada", async () => {
    signedInBackend({
      me: meFixture({
        role: "company_manager",
        extraPermissions: IMPORT_PERMISSIONS,
        branch: null,
      }),
      branches: [
        branch(ids.branchA, ids.companyA, "Sucursal Centro"),
        branch(ids.branchA2, ids.companyA, "Sucursal Norte"),
      ],
    });
    await renderApp({ route: ROUTE });

    expect(await screen.findByRole("heading", { name: "Elija una sucursal" })).toBeTruthy();
    expect(screen.queryByRole("radiogroup", { name: "Qué va a importar" })).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("sin permiso para importar la pantalla no se muestra", async () => {
    manager(["platform.customer.read"], []);
    await renderApp({ route: ROUTE });

    expect(
      await screen.findByRole("heading", { name: "No tiene permiso para ver esto" }),
    ).toBeTruthy();
  });
});
