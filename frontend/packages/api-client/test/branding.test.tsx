import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  ApiError,
  createApiClient,
  createCsrfStore,
  toBrandingFormData,
  updateBranding,
  type BrandingChanges,
} from "../src";

// Node environment (no jsdom): real multipart bodies, with real files, through the real client.
const BASE = "http://api.test";
const ORG = "0198f0a0-0000-7000-8000-000000000a01";
const COMPANY = "0198f0a0-0000-7000-8000-000000000a02";
const URL_PATH = `${BASE}/api/v1/organizations/${ORG}/companies/${COMPANY}/branding`;
const saved = {
  data: {
    brand_name: "Salón Estilo",
    tagline: null,
    primary_color: "#8B2F5C",
    secondary_color: null,
    accent_color: null,
    font_choice: null,
    assets: { logo: null, banner: null, favicon: null },
  },
};

const changes = (overrides: Partial<BrandingChanges> = {}): BrandingChanges => ({
  text: {
    brand_name: "Salón Estilo",
    tagline: "",
    primary_color: "#8B2F5C",
    secondary_color: "",
    accent_color: "",
    font_choice: "nunito",
  },
  files: {},
  remove: [],
  ...overrides,
});

const server = setupServer();
beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe("toBrandingFormData", () => {
  test("incluye todos los textos, aun vacíos (un campo vacío vuelve al default)", () => {
    const form = toBrandingFormData(changes());

    expect([...form.keys()]).toEqual([
      "brand_name",
      "tagline",
      "primary_color",
      "secondary_color",
      "accent_color",
      "font_choice",
    ]);
    expect(form.get("tagline")).toBe("");
  });

  test("agrega los archivos con su nombre y los remove[] repetidos", () => {
    const logo = new File([new Uint8Array([1, 2, 3])], "logo.png", { type: "image/png" });

    const form = toBrandingFormData(changes({ files: { logo }, remove: ["banner", "favicon"] }));

    expect((form.get("logo") as File).name).toBe("logo.png");
    expect(form.getAll("remove[]")).toEqual(["banner", "favicon"]);
  });

  test("adversarial: sin archivos ni quitados no inventa partes", () => {
    const form = toBrandingFormData(changes());

    expect(form.has("logo")).toBe(false);
    expect(form.has("remove[]")).toBe(false);
  });
});

describe("updateBranding", () => {
  const client = () => {
    const csrf = createCsrfStore();
    csrf.set("tok");
    return createApiClient({ baseUrl: BASE, csrf });
  };
  const target = { organizationId: ORG, companyId: COMPANY };

  test("envía multipart con el archivo real y el token CSRF", async () => {
    let received: { form: FormData; csrf: string | null; type: string | null } | undefined;
    server.use(
      http.patch(URL_PATH, async ({ request }) => {
        received = {
          form: await request.formData(),
          csrf: request.headers.get("x-csrf-token"),
          type: request.headers.get("content-type"),
        };
        return HttpResponse.json(saved);
      }),
    );
    const logo = new File([new Uint8Array([137, 80, 78, 71])], "logo.png", { type: "image/png" });

    const result = await updateBranding(client(), target, changes({ files: { logo } }));

    expect(result).toEqual(saved);
    expect(received!.type).toMatch(/^multipart\/form-data; boundary=/);
    expect(received!.csrf).toBe("tok");
    const sent = received!.form.get("logo") as File;
    expect(sent.name).toBe("logo.png");
    expect(sent.size).toBe(4);
    expect(received!.form.get("font_choice")).toBe("nunito");
  });

  test("adversarial: un 422 rechaza con ApiError y trae los errores por campo", async () => {
    server.use(
      http.patch(URL_PATH, () =>
        HttpResponse.json(
          {
            type: "urn:ceiba:error:request.invalid",
            title: "Inválido",
            status: 422,
            code: "request.invalid",
            errors: [{ field: "logo", code: "invalid_file_type", message: "x" }],
          },
          { status: 422 },
        ),
      ),
    );

    const failure = await updateBranding(client(), target, changes()).catch(
      (error: unknown) => error,
    );

    expect(failure).toBeInstanceOf(ApiError);
    expect(failure).toMatchObject({
      status: 422,
      errors: [{ field: "logo", code: "invalid_file_type" }],
    });
  });

  test("adversarial: un 403 no se confunde con éxito", async () => {
    server.use(
      http.patch(URL_PATH, () =>
        HttpResponse.json(
          { type: "u", title: "Prohibido", status: 403, code: "access.forbidden" },
          { status: 403 },
        ),
      ),
    );

    await expect(updateBranding(client(), target, changes())).rejects.toMatchObject({
      status: 403,
    });
  });
});
