import { ApiError } from "@ceiba/api-client";
import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { BranchForm } from "./branch-form";

async function renderForm(props: Partial<React.ComponentProps<typeof BranchForm>> = {}) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(
    <BranchForm defaultTimeZone="America/Managua" onSubmit={onSubmit} {...props} />,
  );
  return { onSubmit, ...view };
}

describe("BranchForm", () => {
  it("crea con el nombre y la zona horaria por defecto", async () => {
    const { user, onSubmit } = await renderForm();

    expect(screen.getByRole("combobox", { name: "Zona horaria" }).textContent).toContain(
      "America/Managua",
    );
    await user.type(screen.getByLabelText("Nombre"), "  Granada  ");
    await user.click(screen.getByRole("button", { name: "Crear sucursal" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ name: "Granada", time_zone: "America/Managua" });
  });

  it("la zona de la sucursal en contexto es el valor inicial aunque no esté en la lista corta", async () => {
    const { user, onSubmit } = await renderForm({ defaultTimeZone: "Pacific/Galapagos" });

    expect(screen.getByRole("combobox", { name: "Zona horaria" }).textContent).toContain(
      "Pacific/Galapagos",
    );
    await user.type(screen.getByLabelText("Nombre"), "Isla");
    await user.click(screen.getByRole("button", { name: "Crear sucursal" }));

    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({ name: "Isla", time_zone: "Pacific/Galapagos" }),
    );
  });

  it("no envía con el nombre en blanco (solo espacios)", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), "   ");
    await user.click(screen.getByRole("button", { name: "Crear sucursal" }));

    expect(await screen.findByText("Escriba el nombre de la sucursal.")).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("un 422 sobre time_zone se muestra en ese campo", async () => {
    const onSubmit = vi
      .fn()
      .mockRejectedValue(
        new ApiError(422, "tenancy.invalid", "Datos inválidos", [
          { field: "time_zone", code: "invalid", message: "no es una zona horaria válida" },
        ]),
      );
    const { user } = await renderForm({ onSubmit });

    await user.type(screen.getByLabelText("Nombre"), "Granada");
    await user.click(screen.getByRole("button", { name: "Crear sucursal" }));

    expect(await screen.findByText("no es una zona horaria válida")).toBeTruthy();
  });

  it("un 403 queda como error del formulario", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido"));
    const { user } = await renderForm({ onSubmit });

    await user.type(screen.getByLabelText("Nombre"), "Granada");
    await user.click(screen.getByRole("button", { name: "Crear sucursal" }));

    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });
});
