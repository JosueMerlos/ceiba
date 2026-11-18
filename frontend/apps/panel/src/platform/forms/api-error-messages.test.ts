import { ApiError } from "@ceiba/api-client";
import { createI18n } from "@ceiba/i18n";
import { describe, expect, it } from "vitest";
import { apiErrorMessages } from "./api-error-messages";

describe("apiErrorMessages", () => {
  it("un 422 con errores devuelve el mensaje de cada uno", async () => {
    const { t } = await createI18n();
    const error = new ApiError(422, "validation.failed", "Datos inválidos", [
      { field: "slots", code: "overlap", message: "Se cruza con otra franja" },
      { field: "slots", code: "invalid", message: "Franja vacía" },
    ]);

    expect(apiErrorMessages(error, t)).toEqual(["Se cruza con otra franja", "Franja vacía"]);
  });

  it("un 422 sin errores devuelve el título", async () => {
    const { t } = await createI18n();
    const error = new ApiError(422, "validation.failed", "Datos inválidos", []);

    expect(apiErrorMessages(error, t)).toEqual(["Datos inválidos"]);
  });

  it("cualquier otro fallo se describe por su código, no por el texto del servidor (adversarial)", async () => {
    const { t } = await createI18n();
    const server = apiErrorMessages(new ApiError(500, "http.500", "Texto del servidor", []), t);
    const network = apiErrorMessages(new TypeError("fetch failed"), t);

    expect(server).toHaveLength(1);
    expect(server[0]).toMatch(/Ocurrió un problema/);
    expect(server[0]).not.toMatch(/Texto del servidor/);
    expect(network[0]).toMatch(/conexión/);
  });
});
