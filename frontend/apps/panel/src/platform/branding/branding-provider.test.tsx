import { ApiClientProvider, createApiClient, createCsrfStore } from "@ceiba/api-client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it } from "vitest";
import { API, brandingFixture, company, ids, meFixture, problem } from "../../test/fixtures";
import { server } from "../../test/server";
import { MeProvider } from "../me/me-provider";
import { BrandingProvider } from "./branding-provider";

const root = document.documentElement;
const cssVar = (name: string) => root.style.getPropertyValue(name);

afterEach(() => {
  root.removeAttribute("style");
  document.head.querySelectorAll("link[rel~='icon']").forEach((link) => link.remove());
});

const brandingFor = (slug: string, body: ReturnType<typeof brandingFixture> | number) =>
  server.use(
    http.get(`${API}/api/public/v1/c/${slug}/branding`, () =>
      typeof body === "number"
        ? HttpResponse.json(problem(body, "resource.not_found"), { status: body })
        : HttpResponse.json(body),
    ),
  );

function Providers({ slug, children }: { slug: string; children: ReactNode }) {
  const me = meFixture({ company: company(ids.companyA, slug.replace("-", " ")) }).data;
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <ApiClientProvider client={createApiClient({ baseUrl: API, csrf: createCsrfStore() })}>
        <MeProvider me={me}>
          <BrandingProvider>{children}</BrandingProvider>
        </MeProvider>
      </ApiClientProvider>
    </QueryClientProvider>
  );
}

describe("BrandingProvider", () => {
  it("aplica en :root la marca de la empresa del contexto, leída del endpoint público por slug", async () => {
    brandingFor("salon-estilo", brandingFixture({ primary_color: "#8B2F5C" }));

    render(
      <Providers slug="salon-estilo">
        <p>contenido</p>
      </Providers>,
    );

    await waitFor(() => expect(cssVar("--brand-primary")).toBe("#8B2F5C"));
    expect(cssVar("--brand-primary-foreground")).toBe("var(--palette-kapok-0)");
    expect(screen.getByText("contenido")).toBeTruthy();
  });

  it("con #FFFF00 escribe texto oscuro y el borde de foco de la paleta", async () => {
    brandingFor("salon-estilo", brandingFixture({ primary_color: "#FFFF00" }));

    render(<Providers slug="salon-estilo">{null}</Providers>);

    await waitFor(() => expect(cssVar("--brand-primary")).toBe("#FFFF00"));
    expect(cssVar("--brand-primary-foreground")).toBe("var(--palette-kapok-900)");
    expect(cssVar("--ring")).toBe("var(--palette-canopy-500)");
  });

  it("una empresa sin marca no escribe nada (paleta de la plataforma)", async () => {
    brandingFor("salon-estilo", brandingFixture());

    render(<Providers slug="salon-estilo">{null}</Providers>);

    await waitFor(() => expect(server.listHandlers().length).toBeGreaterThan(0));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(root.getAttribute("style") ?? "").toBe("");
  });

  it("adversarial: un 404 del endpoint público no rompe el panel ni deja variables", async () => {
    brandingFor("salon-estilo", 404);

    render(
      <Providers slug="salon-estilo">
        <p>contenido</p>
      </Providers>,
    );

    expect(await screen.findByText("contenido")).toBeTruthy();
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(cssVar("--brand-primary")).toBe("");
  });

  it("al cambiar de empresa limpia las variables de la anterior", async () => {
    brandingFor("salon-estilo", brandingFixture({ primary_color: "#8B2F5C" }));
    brandingFor("clinica-sonrisa", brandingFixture());
    const { rerender } = render(<Providers slug="salon-estilo">{null}</Providers>);
    await waitFor(() => expect(cssVar("--brand-primary")).toBe("#8B2F5C"));

    rerender(<Providers slug="clinica-sonrisa">{null}</Providers>);

    await waitFor(() => expect(cssVar("--brand-primary")).toBe(""));
  });

  it("cambia el favicon si hay uno y lo restaura al desmontar", async () => {
    const original = document.createElement("link");
    original.rel = "icon";
    original.href = "/favicon.ico";
    document.head.append(original);
    brandingFor(
      "salon-estilo",
      brandingFixture({
        assets: {
          logo: null,
          banner: null,
          favicon: { icon32: "/api/storage/favicon32.png", icon180: "/api/storage/f180.png" },
        },
      }),
    );

    const { unmount } = render(<Providers slug="salon-estilo">{null}</Providers>);

    await waitFor(() => expect(original.getAttribute("href")).toBe("/api/storage/favicon32.png"));
    unmount();
    expect(original.getAttribute("href")).toBe("/favicon.ico");
  });
});
