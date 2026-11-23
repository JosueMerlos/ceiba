import { screen, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { meFixture } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { server, signedInBackend } from "../../test/server";
import {
  CUSTOMER_PERMISSIONS,
  customerFixture,
  customerId,
  customersUrl,
  historyUrl,
  visitFixture,
} from "./test-support";

const ROUTE = `/customers/${customerId}`;
const page = (data: unknown[]) => ({ data, page: { has_more: false, next_cursor: null } });

const backend = ({
  modules = ["appointments"],
  customer = customerFixture(),
  visits = [visitFixture()],
} = {}) => {
  signedInBackend({
    me: meFixture({ role: "receptionist", modules, extraPermissions: CUSTOMER_PERMISSIONS }),
  });
  server.use(
    http.get(`${customersUrl()}/${customerId}`, () => HttpResponse.json({ data: customer })),
    http.get(historyUrl(), () => HttpResponse.json(page(visits))),
  );
};

describe("ficha de cliente", () => {
  it("muestra nombre, teléfono y desde cuándo es cliente, en la zona de la sucursal", async () => {
    backend();
    await renderApp({ route: ROUTE });

    expect(await screen.findByRole("heading", { level: 1, name: "Fernanda Ruiz" })).toBeTruthy();
    expect(screen.getByText("+505 8812 3456. Cliente desde marzo de 2026.")).toBeTruthy();
  });

  it("el historial usa la fecha de la sucursal aunque el navegador esté en otra zona, con su estado", async () => {
    // 03:30 UTC del 2 de noviembre es el 1 de noviembre, 21:30, en Managua.
    backend({
      visits: [
        visitFixture({ status: "no_show", id: "0198f0a0-0000-7000-8000-00000000d002" }),
        visitFixture({ status: "cancelled", id: "0198f0a0-0000-7000-8000-00000000d003" }),
        visitFixture(),
      ],
    });
    await renderApp({ route: ROUTE });

    const history = await screen.findByRole("region", { name: "Historial" });
    const rows = await within(history).findAllByRole("row");
    expect(within(rows[1]!).getByText("1 de noviembre de 2026 a las 9:30 p. m.")).toBeTruthy();
    expect(within(rows[1]!).getByText("Corte de cabello")).toBeTruthy();
    expect(within(rows[1]!).getByText("Rosa Martínez")).toBeTruthy();
    expect(
      rows.slice(1).map((row) => within(row).getAllByRole("cell").at(-1)!.textContent),
    ).toEqual(["No asistió", "Cancelada", "Completada"]);
    expect(within(history).getByText(/Solo las citas de Sucursal Centro/)).toBeTruthy();
  });

  it("sin el módulo de citas no pide el historial y lo explica", async () => {
    backend({ modules: [] });
    await renderApp({ route: ROUTE });

    expect(
      await screen.findByText("El historial de citas aparece cuando la empresa usa la agenda."),
    ).toBeTruthy();
  });

  it("recordatorios: ningún consentimiento está registrado todavía", async () => {
    backend();
    await renderApp({ route: ROUTE });

    const reminders = await screen.findByRole("region", { name: "Recordatorios" });
    expect(within(reminders).getByText("Sin consentimiento registrado")).toBeTruthy();
  });

  it("editar datos abre el panel con los datos actuales y guarda solo lo cambiado", async () => {
    backend({ customer: customerFixture({ notes: "Prefiere citas temprano" }) });
    let body: unknown;
    server.use(
      http.patch(`${customersUrl()}/${customerId}`, async ({ request }) => {
        body = await request.json();
        return HttpResponse.json({ data: customerFixture({ full_name: "Fernanda Ruiz López" }) });
      }),
    );
    const { user } = await renderApp({ route: ROUTE });

    await user.click(await screen.findByRole("button", { name: "Editar datos" }));
    const name = screen.getByLabelText("Nombre completo");
    await user.clear(name);
    await user.type(name, "Fernanda Ruiz López");
    await user.click(screen.getByRole("button", { name: "Guardar cliente" }));

    await screen.findByText("Cliente actualizado");
    expect(body).toEqual({ full_name: "Fernanda Ruiz López" });
  });

  it("un cliente archivado lo dice y conserva su historial", async () => {
    backend({ customer: customerFixture({ archived_at: "2026-11-10T12:00:00.000Z" }) });
    await renderApp({ route: ROUTE });

    expect(await screen.findByText("Archivado")).toBeTruthy();
    expect(await screen.findByText("Corte de cabello")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Editar datos" })).toBeNull();
  });
});
