import { ApiError } from "@ceiba/api-client";
import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { service } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ServiceForm } from "./service-form";

async function renderForm(props: Partial<React.ComponentProps<typeof ServiceForm>> = {}) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(<ServiceForm currency="NIO" onSubmit={onSubmit} {...props} />);
  return { onSubmit, ...view };
}

describe("ServiceForm", () => {
  it("crea: convierte el precio en unidades mayores a price_minor y activa el servicio por defecto", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), "Corte clásico");
    await user.type(screen.getByLabelText("Duración (minutos)"), "45");
    await user.type(screen.getByLabelText("Precio (NIO)"), "250.50");
    await user.click(screen.getByRole("button", { name: "Crear servicio" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({
      name: "Corte clásico",
      duration_minutes: 45,
      buffer_after_minutes: 0,
      price_minor: 25050,
      active: true,
    });
  });

  it("edita: precarga los valores del servicio y envía el tiempo libre y el estado cambiados", async () => {
    const { user, onSubmit } = await renderForm({
      service: service("s1", "Tinte", {
        duration_minutes: 90,
        price_minor: 80000,
        buffer_after_minutes: 10,
      }),
    });

    expect(screen.getByLabelText("Precio (NIO)")).toHaveProperty("value", "800.00");
    expect(screen.getByLabelText("Tiempo libre después (minutos)")).toHaveProperty("value", "10");
    await user.clear(screen.getByLabelText("Tiempo libre después (minutos)"));
    await user.type(screen.getByLabelText("Tiempo libre después (minutos)"), "15");
    await user.click(screen.getByRole("switch", { name: "Disponible para reservar" }));
    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({
      name: "Tinte",
      duration_minutes: 90,
      buffer_after_minutes: 15,
      price_minor: 80000,
      active: false,
    });
  });

  it("no envía con datos inválidos y marca cada campo (nombre vacío, duración 0, precio con letras)", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Duración (minutos)"), "0");
    await user.type(screen.getByLabelText("Precio (NIO)"), "doscientos");
    await user.click(screen.getByRole("button", { name: "Crear servicio" }));

    expect(await screen.findByText("Escriba el nombre del servicio.")).toBeTruthy();
    expect(
      screen.getByText("La duración debe ser un número entero de minutos, mayor que cero."),
    ).toBeTruthy();
    expect(screen.getByText("Escriba un precio válido, por ejemplo 250 o 250.50.")).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("un 422 del servidor se muestra en el campo que corresponde (price_minor -> precio)", async () => {
    const onSubmit = vi
      .fn()
      .mockRejectedValue(
        new ApiError(422, "validation.failed", "Datos inválidos", [
          { field: "price_minor", code: "invalid", message: "es demasiado grande" },
        ]),
      );
    const { user } = await renderForm({ onSubmit });

    await user.type(screen.getByLabelText("Nombre"), "Corte");
    await user.type(screen.getByLabelText("Duración (minutos)"), "30");
    await user.type(screen.getByLabelText("Precio (NIO)"), "10");
    await user.click(screen.getByRole("button", { name: "Crear servicio" }));

    expect(await screen.findByText("es demasiado grande")).toBeTruthy();
    expect(screen.getByLabelText("Precio (NIO)").getAttribute("aria-invalid")).toBe("true");
  });

  it("un 403 se muestra como error del formulario, no se pierde", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido"));
    const { user } = await renderForm({ onSubmit });

    await user.type(screen.getByLabelText("Nombre"), "Corte");
    await user.type(screen.getByLabelText("Duración (minutos)"), "30");
    await user.type(screen.getByLabelText("Precio (NIO)"), "10");
    await user.click(screen.getByRole("button", { name: "Crear servicio" }));

    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });

  it("de solo lectura los campos están deshabilitados y no hay botón de guardar", async () => {
    await renderForm({ service: service("s1", "Tinte"), readOnly: true });

    expect(screen.getByLabelText("Nombre")).toHaveProperty("disabled", true);
    expect(screen.getByLabelText("Precio (NIO)")).toHaveProperty("disabled", true);
    expect(screen.queryByRole("button", { name: "Guardar cambios" })).toBeNull();
  });
});
