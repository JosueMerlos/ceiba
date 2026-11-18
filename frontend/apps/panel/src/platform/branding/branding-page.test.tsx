import { screen, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { API, brandingFixture, company, ids, meFixture, problem } from "../../test/fixtures";
import { renderApp } from "../../test/render-app";
import { server, signedInBackend } from "../../test/server";

const PERMISSION = "platform.branding.update";
const ROUTE = "/settings/branding";
const salon = company(ids.companyA, "Salon Estilo");
const brandingUrl = `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}/branding`;

const manager = () =>
  signedInBackend({
    me: meFixture({ role: "company_manager", company: salon, extraPermissions: [PERMISSION] }),
    companies: [salon],
  });

const stubBranding = (body = brandingFixture()) =>
  server.use(
    http.get(brandingUrl, () => HttpResponse.json(body)),
    http.get(`${API}/api/public/v1/c/salon-estilo/branding`, () => HttpResponse.json(body)),
  );

const preview = () => screen.getByRole("region", { name: "Vista previa de la marca" });
const scope = () => preview().querySelector<HTMLElement>("[data-brand-scope]")!;

let created = 0;
beforeEach(() => {
  created = 0;
  URL.createObjectURL = vi.fn(() => `blob:preview-${++created}`);
  URL.revokeObjectURL = vi.fn();
});
afterEach(() => vi.restoreAllMocks());

// Tests that read the multipart body avoid files: jsdom's File cannot cross into undici (the fetch behind MSW), so the
// real file payload is covered by the api-client test, which runs without jsdom.

const png = (name = "logo.png", type = "image/png") =>
  new File([new Uint8Array([137, 80])], name, { type });

describe("pantalla de marca", () => {
  it("un company_manager ve la pantalla y el ítem de menú, y la vista previa cambia al escribir #FFFF00", async () => {
    manager();
    stubBranding();
    const { user } = await renderApp({ route: ROUTE });

    expect(await screen.findByRole("heading", { name: "Marca de la empresa" })).toBeTruthy();
    const nav = screen.getByRole("navigation", { name: "Navegación principal" });
    expect(within(nav).getByRole("link", { name: "Marca" })).toBeTruthy();

    await user.type(screen.getByLabelText("Color principal"), "#FFFF00");

    expect(scope().style.getPropertyValue("--brand-primary")).toBe("#FFFF00");
    expect(scope().style.getPropertyValue("--brand-primary-foreground")).toBe(
      "var(--palette-kapok-900)",
    );
    expect(scope().style.getPropertyValue("--ring")).toBe("var(--palette-canopy-500)");
    expect(screen.getByText(/el texto se mostrará oscuro para que se lea/i)).toBeTruthy();
    expect(screen.getByText(/borde de foco usará el verde de Ceiba/i)).toBeTruthy();
    expect(within(preview()).getByText("Reservar cita")).toBeTruthy();
  });

  it("avisa cuando un tono medio no admite texto legible y la vista previa usa el color de la plataforma", async () => {
    manager();
    stubBranding();
    const { user } = await renderApp({ route: ROUTE });

    await screen.findByRole("heading", { name: "Marca de la empresa" });
    await user.type(screen.getByLabelText("Color principal"), "#777777");

    expect(scope().style.getPropertyValue("--brand-primary")).toBe("");
    expect(screen.getByText(/no permite un texto legible/i)).toBeTruthy();
  });

  it("sin permiso: muestra 'sin acceso', no hay ítem de menú y no se pide la marca", async () => {
    signedInBackend({
      me: meFixture({ role: "receptionist", company: salon }),
      companies: [salon],
    });
    await renderApp({ route: ROUTE });

    expect(
      await screen.findByRole("heading", { name: "No tiene permiso para ver esto" }),
    ).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Marca" })).toBeNull();
  });

  it("precarga lo guardado: nombre, lema, colores y fuente", async () => {
    manager();
    stubBranding(
      brandingFixture({
        brand_name: "Salón Estilo",
        tagline: "Su estilo, su momento",
        primary_color: "#8B2F5C",
        font_choice: "nunito",
      }),
    );
    await renderApp({ route: ROUTE });

    expect(await screen.findByDisplayValue("Salón Estilo")).toBeTruthy();
    expect(screen.getByDisplayValue("#8B2F5C")).toBeTruthy();
    expect((screen.getByRole("radio", { name: /Nunito/ }) as HTMLInputElement).checked).toBe(true);
  });

  it("guarda con multipart y token CSRF, con los textos que el usuario escribió", async () => {
    manager();
    stubBranding();
    let received: { form: FormData; csrf: string | null; contentType: string | null } | undefined;
    server.use(
      http.patch(brandingUrl, async ({ request }) => {
        received = {
          form: await request.formData(),
          csrf: request.headers.get("x-csrf-token"),
          contentType: request.headers.get("content-type"),
        };
        return HttpResponse.json(brandingFixture({ brand_name: "Salón Estilo" }));
      }),
    );
    const { user } = await renderApp({ route: ROUTE });
    await user.type(await screen.findByLabelText("Nombre comercial"), "Salón Estilo");
    await user.type(screen.getByLabelText("Color principal"), "#8B2F5C");

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(received).toBeDefined());
    expect(received!.csrf).toBe("csrf-de-prueba");
    expect(received!.form.get("brand_name")).toBe("Salón Estilo");
    expect(received!.form.get("primary_color")).toBe("#8B2F5C");
    expect(received!.contentType).toMatch(/^multipart\/form-data; boundary=/);
    expect(received!.form.has("logo")).toBe(false);
    expect(await screen.findByText("Marca guardada")).toBeTruthy();
  });

  it("un 422 por un archivo inválido se muestra bajo el campo del logo y se anuncia", async () => {
    manager();
    stubBranding();
    server.use(
      http.patch(brandingUrl, () =>
        HttpResponse.json(
          {
            ...problem(422, "request.invalid"),
            errors: [{ field: "logo", code: "invalid_file_type", message: "tipo inválido" }],
          },
          { status: 422 },
        ),
      ),
    );
    const { user } = await renderApp({ route: ROUTE });
    await user.upload(await screen.findByLabelText("Logo"), png("svg-as.png"));

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("El archivo no es una imagen PNG, JPG o WebP.");
    const input = screen.getByLabelText("Logo");
    expect(input.getAttribute("aria-invalid")).toBe("true");
    expect(input.getAttribute("aria-describedby")).toContain(alert.id);
  });

  it("un 413 problem+json se muestra como alerta en el formulario", async () => {
    manager();
    stubBranding();
    server.use(
      http.patch(brandingUrl, () =>
        HttpResponse.json(problem(413, "request.too_large"), { status: 413 }),
      ),
    );
    const { user } = await renderApp({ route: ROUTE });
    await user.upload(await screen.findByLabelText("Logo"), png());

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe(
      "Los archivos pesan demasiado en total. Elija unos más livianos.",
    );
  });

  it("un 413 del proxy que no es problem+json también se muestra como alerta", async () => {
    manager();
    stubBranding();
    server.use(
      http.patch(brandingUrl, () => new HttpResponse("Request Entity Too Large", { status: 413 })),
    );
    const { user } = await renderApp({ route: ROUTE });
    await user.type(await screen.findByLabelText("Nombre comercial"), "Salón");

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe(
      "Los archivos pesan demasiado en total. Elija unos más livianos.",
    );
  });

  it("un archivo que supera el límite de su tipo se bloquea antes de enviar nada", async () => {
    manager();
    stubBranding();
    let requests = 0;
    server.use(
      http.patch(brandingUrl, () => {
        requests += 1;
        return HttpResponse.json(brandingFixture());
      }),
    );
    const { user } = await renderApp({ route: ROUTE });
    const big = new File([new Uint8Array(200 * 1024 + 1)], "favicon.png", { type: "image/png" });
    await user.upload(await screen.findByLabelText("Ícono de pestaña"), big);

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("El archivo pesa demasiado. Elija uno más liviano.");
    expect(screen.getByLabelText("Ícono de pestaña").getAttribute("aria-invalid")).toBe("true");
    expect(requests).toBe(0);
  });

  it("adversarial: un color mal escrito se señala bajo su campo y no se envía nada", async () => {
    manager();
    stubBranding();
    const patch = vi.fn();
    server.use(http.patch(brandingUrl, () => (patch(), HttpResponse.json(brandingFixture()))));
    const { user } = await renderApp({ route: ROUTE });
    await user.type(await screen.findByLabelText("Color de acento"), "#12");

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    expect((await screen.findByRole("alert")).textContent).toBe(
      "Use el formato #RRGGBB, por ejemplo #1D6C4E.",
    );
    expect(patch).not.toHaveBeenCalled();
  });

  it("quitar un archivo guardado envía remove[]; la vista previa local se libera al reemplazar y al quitar", async () => {
    manager();
    stubBranding(
      brandingFixture({
        assets: {
          logo: { x1: "/api/storage/logo1.webp", x2: "/api/storage/logo2.webp" },
          banner: null,
          favicon: null,
        },
      }),
    );
    let form: FormData | undefined;
    server.use(
      http.patch(brandingUrl, async ({ request }) => {
        form = await request.formData();
        return HttpResponse.json(brandingFixture());
      }),
    );
    const { user } = await renderApp({ route: ROUTE });
    await user.click(await screen.findByRole("button", { name: "Quitar Logo" }));
    await user.upload(screen.getByLabelText("Banner"), png("a.png"));
    await user.upload(screen.getByLabelText("Banner"), png("b.png"));
    await user.click(screen.getByRole("button", { name: "Quitar Banner" }));

    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:preview-1");
    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(form).toBeDefined());
    expect(form!.getAll("remove[]")).toEqual(["logo"]);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:preview-2");
    expect(form!.has("banner")).toBe(false);
  });

  it("el panel de edición se contrae y se expande con aria-expanded", async () => {
    manager();
    stubBranding();
    const { user } = await renderApp({ route: ROUTE });
    const toggle = await screen.findByRole("button", { name: "Ocultar el panel de edición" });
    expect(toggle.getAttribute("aria-expanded")).toBe("true");

    await user.click(toggle);

    const collapsed = screen.getByRole("button", { name: "Mostrar el panel de edición" });
    expect(collapsed.getAttribute("aria-expanded")).toBe("false");
    expect(screen.queryByRole("textbox", { name: "Nombre comercial" })).toBeNull();
  });

  it("el panel vive en la columna contextual: se cierra desde su botón y conserva lo escrito, el archivo y los errores al reabrirlo", async () => {
    manager();
    stubBranding();
    const { user } = await renderApp({ route: ROUTE });
    const panel = () => screen.queryByRole("complementary", { name: "Personalizar" });
    await user.type(await screen.findByLabelText("Color principal"), "#12");
    await user.upload(screen.getByLabelText("Logo"), png());
    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));
    expect(await screen.findByText("Use el formato #RRGGBB, por ejemplo #1D6C4E.")).toBeTruthy();

    await user.click(within(panel()!).getByRole("button", { name: "Cerrar el panel de edición" }));

    expect(panel()).toBeNull();
    expect(
      screen
        .getByRole("button", { name: "Mostrar el panel de edición" })
        .getAttribute("aria-expanded"),
    ).toBe("false");
    expect(within(preview()).getByAltText("Logo de Salon Estilo")).toBeTruthy();

    await user.click(screen.getByRole("button", { name: "Mostrar el panel de edición" }));

    expect((screen.getByLabelText("Color principal") as HTMLInputElement).value).toBe("#12");
    expect(screen.getByText("Use el formato #RRGGBB, por ejemplo #1D6C4E.")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Quitar Logo" })).toBeTruthy();
  });

  it("pulsar Enter en un campo del panel guarda la marca", async () => {
    manager();
    stubBranding();
    let received: FormData | undefined;
    server.use(
      http.patch(brandingUrl, async ({ request }) => {
        received = await request.formData();
        return HttpResponse.json(brandingFixture({ brand_name: "Salón" }));
      }),
    );
    const { user } = await renderApp({ route: ROUTE });

    await user.type(await screen.findByLabelText("Nombre comercial"), "Salón{Enter}");

    await waitFor(() => expect(received).toBeDefined());
    expect(received!.get("brand_name")).toBe("Salón");
  });
});
