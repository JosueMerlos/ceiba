import { createI18n, I18nextProvider } from "@ceiba/i18n";
import { render, screen, waitFor } from "@testing-library/react";
import { http, HttpResponse, type JsonBodyType } from "msw";
import { afterEach, describe, expect, it } from "vitest";
import { App } from "../App";
import { server } from "../test/server";

const root = document.documentElement;
const cssVar = (name: string) => root.style.getPropertyValue(name);

const branding = (overrides: Record<string, unknown> = {}) => ({
  data: {
    brand_name: null,
    tagline: null,
    primary_color: null,
    secondary_color: null,
    accent_color: null,
    font_choice: null,
    assets: { logo: null, banner: null, favicon: null },
    ...overrides,
  },
});

const serve = (slug: string, body: JsonBodyType, status = 200) =>
  server.use(
    http.get(`*/api/public/v1/c/${slug}/branding`, () => HttpResponse.json(body, { status })),
  );

async function renderAt(path: string) {
  window.history.pushState({}, "", path);
  const i18n = await createI18n();
  return render(
    <I18nextProvider i18n={i18n}>
      <App />
    </I18nextProvider>,
  );
}

afterEach(() => root.removeAttribute("style"));

describe("página pública con marca", () => {
  it("con marca: aplica los colores en :root y pinta logo con x1/x2, banner con ambas proporciones, nombre y lema", async () => {
    serve(
      "salon-estilo",
      branding({
        brand_name: "Salón Estilo",
        tagline: "Su estilo, su momento",
        primary_color: "#8B2F5C",
        assets: {
          logo: { x1: "/api/storage/logo-x1.webp", x2: "/api/storage/logo-x2.webp" },
          banner: {
            wide: "/api/storage/banner-wide.webp",
            standard: "/api/storage/banner-4x3.webp",
          },
          favicon: {
            icon32: "/api/storage/favicon-32.png",
            icon180: "/api/storage/favicon-180.png",
          },
        },
      }),
    );

    const { container } = await renderAt("/c/salon-estilo");

    expect(await screen.findByRole("heading", { name: "Salón Estilo" })).toBeTruthy();
    expect(screen.getByText("Su estilo, su momento")).toBeTruthy();
    expect(cssVar("--brand-primary")).toBe("#8B2F5C");

    const logo = screen.getByRole("img", { name: "Logo de Salón Estilo" });
    expect(logo.getAttribute("srcset")).toBe(
      "/api/storage/logo-x1.webp 1x, /api/storage/logo-x2.webp 2x",
    );

    const picture = container.querySelector("picture");
    expect(picture?.querySelector("source")?.getAttribute("srcset")).toBe(
      "/api/storage/banner-wide.webp",
    );
    expect(picture?.querySelector("img")?.getAttribute("src")).toBe("/api/storage/banner-4x3.webp");

    await waitFor(() =>
      expect(document.head.querySelector("link[rel~='icon']")?.getAttribute("href")).toBe(
        "/api/storage/favicon-32.png",
      ),
    );
  });

  it("sin marca: no emite variables y muestra la marca de la plataforma", async () => {
    serve("clinica-sonrisa", branding());

    const { container } = await renderAt("/c/clinica-sonrisa");

    await waitFor(() => expect(container.querySelector("svg")).toBeTruthy());
    expect(root.getAttribute("style") ?? "").not.toContain("--brand");
    expect(screen.queryByRole("img")).toBeNull();
    expect(container.querySelector("picture")).toBeNull();
  });

  it("Figtree es la tipografía de la plataforma: no escribe --brand-font", async () => {
    serve("figtree-co", branding({ font_choice: "figtree", primary_color: "#8B2F5C" }));

    await renderAt("/c/figtree-co");

    await waitFor(() => expect(cssVar("--brand-primary")).toBe("#8B2F5C"));
    expect(cssVar("--brand-font")).toBe("");
  });

  it("empresa inexistente (404): pantalla de no encontrada con la paleta base", async () => {
    serve("no-existe", { status: 404, code: "resource.not_found" }, 404);

    await renderAt("/c/no-existe");

    expect(
      await screen.findByRole("heading", { name: "No encontramos este negocio" }),
    ).toBeTruthy();
    expect(root.getAttribute("style") ?? "").not.toContain("--brand");
  });

  it("sin slug: conserva la pantalla de reserva de siempre y no consulta la API", async () => {
    await renderAt("/c/");

    expect(screen.getByRole("heading", { name: "Reserve su cita" })).toBeTruthy();
  });
});

describe("logo sin nombre de marca", () => {
  it("usa un texto alternativo genérico en lugar de dejarlo incompleto", async () => {
    serve(
      "sin-nombre",
      branding({
        assets: {
          logo: { x1: "/api/storage/logo-x1.webp", x2: null },
          banner: null,
          favicon: null,
        },
      }),
    );
    await renderAt("/c/sin-nombre");
    const logo = await screen.findByRole("img", { name: "Logo del negocio" });
    expect(logo.getAttribute("src")).toBe("/api/storage/logo-x1.webp");
  });
});
