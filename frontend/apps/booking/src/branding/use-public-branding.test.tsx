import { render, renderHook, screen, waitFor } from "@testing-library/react";
import { I18nextProvider } from "@ceiba/i18n";
import { createBookingI18n } from "../i18n";
import { http, HttpResponse } from "msw";
import { afterEach, describe, expect, it } from "vitest";
import { App } from "../App";
import { server } from "../test/server";
import { slugFromPath, usePublicBranding } from "./use-public-branding";

const root = document.documentElement;
afterEach(() => root.removeAttribute("style"));

const brandOf = (name: string) => ({
  data: {
    brand_name: name,
    tagline: null,
    primary_color: null,
    secondary_color: null,
    accent_color: null,
    font_choice: null,
    assets: { logo: null, banner: null, favicon: null },
  },
});

describe("slugFromPath", () => {
  it("decodifica el slug de /c/:slug", () => {
    expect(slugFromPath("/c/salon%20estilo")).toBe("salon estilo");
  });

  it("una codificación malformada no lanza: devuelve el segmento tal cual", () => {
    expect(() => slugFromPath("/c/%E0%A4")).not.toThrow();
    expect(slugFromPath("/c/%E0%A4")).toBe("%E0%A4");
  });
});

describe("usePublicBranding", () => {
  it("un slug malformado en la URL se trata como empresa no encontrada, sin romper la página", async () => {
    server.use(
      http.get("*/api/public/v1/c/:slug/branding", () => new HttpResponse(null, { status: 404 })),
    );
    window.history.pushState({}, "", "/c/%E0%A4");
    const i18n = await createBookingI18n();

    render(
      <I18nextProvider i18n={i18n}>
        <App />
      </I18nextProvider>,
    );

    expect(
      await screen.findByRole("heading", { name: i18n.t("booking:notFound.title") }),
    ).toBeTruthy();
  });

  it("al cambiar el slug no conserva la marca anterior mientras carga la nueva", async () => {
    server.use(
      http.get("*/api/public/v1/c/uno/branding", () => HttpResponse.json(brandOf("Uno"))),
      http.get("*/api/public/v1/c/dos/branding", () => new Promise(() => {})),
    );
    const { result, rerender } = renderHook(({ slug }) => usePublicBranding(slug), {
      initialProps: { slug: "uno" as string | null },
    });
    await waitFor(() => expect(result.current.status).toBe("ready"));

    rerender({ slug: "dos" });

    expect(result.current).toEqual({ status: "loading" });
  });

  it("si el slug pasa a null vuelve a cargando y quita la marca aplicada", async () => {
    server.use(
      http.get("*/api/public/v1/c/uno/branding", () =>
        HttpResponse.json({ data: { ...brandOf("Uno").data, primary_color: "#8B2F5C" } }),
      ),
    );
    const { result, rerender } = renderHook(({ slug }) => usePublicBranding(slug), {
      initialProps: { slug: "uno" as string | null },
    });
    await waitFor(() => expect(result.current.status).toBe("ready"));

    rerender({ slug: null });

    expect(result.current).toEqual({ status: "loading" });
  });
});
