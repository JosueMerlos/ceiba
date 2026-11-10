import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AppLayout, StatusPage } from "../src";

describe("AppLayout", () => {
  it("expone los puntos de referencia: cabecera, navegación principal y contenido", () => {
    render(
      <AppLayout
        skipLinkLabel="Saltar al contenido"
        navigationLabel="Principal"
        brand={<span>Ceiba</span>}
        navigation={<a href="/agenda">Agenda</a>}
        actions={<button type="button">Cuenta</button>}
      >
        <h1>Hoy</h1>
      </AppLayout>,
    );

    expect(screen.getByRole("banner")).toBeTruthy();
    const nav = screen.getByRole("navigation", { name: "Principal" });
    expect(within(nav).getByRole("link", { name: "Agenda" })).toBeTruthy();
    expect(within(screen.getByRole("main")).getByRole("heading", { name: "Hoy" })).toBeTruthy();
  });

  it("ofrece un enlace para saltar al contenido que apunta al <main>", () => {
    render(
      <AppLayout
        skipLinkLabel="Saltar al contenido"
        navigationLabel="Principal"
        brand="Ceiba"
        navigation={null}
        actions={null}
      >
        <p>x</p>
      </AppLayout>,
    );

    const link = screen.getByRole("link", { name: "Saltar al contenido" });
    expect(link.getAttribute("href")).toBe(`#${screen.getByRole("main").id}`);
  });
});

describe("StatusPage", () => {
  it("muestra título, descripción y la acción", () => {
    render(
      <StatusPage
        code="404"
        title="No encontrado"
        description="La página no existe."
        action={<a href="/">Volver al inicio</a>}
      />,
    );

    expect(screen.getByRole("heading", { name: "No encontrado" })).toBeTruthy();
    expect(screen.getByText("La página no existe.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Volver al inicio" })).toBeTruthy();
  });
});
