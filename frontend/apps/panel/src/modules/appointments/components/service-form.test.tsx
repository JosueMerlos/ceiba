import { ApiError } from "@ceiba/api-client";
import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { service } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ServiceForm } from "./service-form";

// The form has no button of its own: the modal's footer submits it through `form={id}`.
async function renderForm(props: Partial<React.ComponentProps<typeof ServiceForm>> = {}) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(
    <>
      <ServiceForm
        id="service-form"
        currency="NIO"
        categories={[]}
        onSubmit={onSubmit}
        {...props}
      />
      <button type="submit" form="service-form">
        Enviar
      </button>
    </>,
  );
  return { onSubmit, ...view };
}

const submit = () => screen.getByRole("button", { name: "Enviar" });

describe("ServiceForm", () => {
  it("crea: 30 minutos por defecto, convierte el precio a price_minor y lo deja disponible", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), "Corte clásico");
    await user.type(screen.getByLabelText("Precio (NIO)"), "250.50");
    await user.click(submit());

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({
      name: "Corte clásico",
      category: null,
      duration_minutes: 30,
      buffer_before_minutes: 0,
      buffer_after_minutes: 0,
      price_minor: 25050,
      active: true,
    });
  });

  it("la duración y los tiempos libres se cambian con los botones, sin escribir minutos", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), "Barba");
    await user.type(screen.getByLabelText("Precio (NIO)"), "120");
    await user.click(screen.getByRole("button", { name: "Sumar 5 minutos a la duración" }));
    const before = screen.getByRole("group", { name: "Preparación antes" });
    await user.click(within(before).getByRole("button", { name: "10 min" }));
    await user.click(screen.getByRole("button", { name: "Sumar 5 minutos al tiempo libre" }));
    await user.click(submit());

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit.mock.calls[0]![0]).toMatchObject({
      duration_minutes: 35,
      buffer_before_minutes: 10,
      buffer_after_minutes: 5,
    });
  });

  it("edita: precarga el servicio y envía la categoría tal como se escribió", async () => {
    const { user, onSubmit } = await renderForm({
      service: service("s1", "Tinte", {
        category: "Color",
        duration_minutes: 90,
        price_minor: 80000,
        buffer_after_minutes: 10,
      }),
    });

    expect(screen.getByLabelText("Precio (NIO)")).toHaveProperty("value", "800.00");
    expect(
      within(screen.getByRole("group", { name: "Duración" })).getByRole("status").textContent,
    ).toBe("1 h 30 min");
    const category = screen.getByRole("combobox", { name: "Categoría (opcional)" });
    expect(category).toHaveProperty("value", "Color");
    await user.clear(category);
    await user.type(category, "  Uñas ");
    await user.click(screen.getByRole("switch", { name: "Disponible para reservar" }));
    await user.click(submit());

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({
      name: "Tinte",
      category: "  Uñas ",
      duration_minutes: 90,
      buffer_before_minutes: 0,
      buffer_after_minutes: 10,
      price_minor: 80000,
      active: false,
    });
  });

  it("sugiere las categorías ya usadas que coinciden con lo escrito y elige una con el teclado", async () => {
    const { user, onSubmit } = await renderForm({ categories: ["Cortes", "Barba", "Color"] });

    await user.type(screen.getByLabelText("Nombre"), "Corte niño");
    await user.type(screen.getByLabelText("Precio (NIO)"), "100");
    const category = screen.getByRole("combobox", { name: "Categoría (opcional)" });
    await user.type(category, "co");

    const list = screen.getByRole("listbox", { name: "Categorías usadas" });
    expect(
      within(list)
        .getAllByRole("option")
        .map((option) => option.textContent),
    ).toEqual(["Cortes", "Color"]);
    await user.keyboard("{ArrowDown}{ArrowDown}{Enter}");
    expect(category).toHaveProperty("value", "Color");
    expect(screen.queryByRole("listbox")).toBeNull();

    await user.click(submit());
    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit.mock.calls[0]![0]).toMatchObject({ category: "Color" });
  });

  it("no envía con datos inválidos y marca cada campo (nombre vacío, precio con letras, categoría de más de 60)", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Precio (NIO)"), "doscientos");
    await user.type(screen.getByRole("combobox", { name: "Categoría (opcional)" }), "x".repeat(61));
    await user.click(submit());

    expect(await screen.findByText("Escriba el nombre del servicio.")).toBeTruthy();
    expect(screen.getByText("Escriba un precio válido, por ejemplo 250 o 250.50.")).toBeTruthy();
    expect(screen.getByText("La categoría admite hasta 60 caracteres.")).toBeTruthy();
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
    await user.type(screen.getByLabelText("Precio (NIO)"), "10");
    await user.click(submit());

    expect(await screen.findByText("es demasiado grande")).toBeTruthy();
    expect(screen.getByLabelText("Precio (NIO)").getAttribute("aria-invalid")).toBe("true");
  });

  it("un 403 se muestra como error del formulario, no se pierde", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido"));
    const { user } = await renderForm({ onSubmit });

    await user.type(screen.getByLabelText("Nombre"), "Corte");
    await user.type(screen.getByLabelText("Precio (NIO)"), "10");
    await user.click(submit());

    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });
});
