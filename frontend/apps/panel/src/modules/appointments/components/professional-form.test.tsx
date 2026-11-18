import { ApiError } from "@ceiba/api-client";
import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { professional } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ProfessionalForm } from "./professional-form";

async function renderForm(props: Partial<React.ComponentProps<typeof ProfessionalForm>> = {}) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(<ProfessionalForm onSubmit={onSubmit} {...props} />);
  return { onSubmit, ...view };
}

describe("ProfessionalForm", () => {
  it("crea: envía el nombre sin espacios sobrantes y activo por defecto", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre para mostrar"), "  Don Efraín  ");
    await user.click(screen.getByRole("button", { name: "Crear profesional" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ display_name: "Don Efraín", active: true });
  });

  it("edita: precarga y envía el estado cambiado", async () => {
    const { user, onSubmit } = await renderForm({
      professional: professional("p1", "Sandra Gómez"),
    });

    expect(screen.getByLabelText("Nombre para mostrar")).toHaveProperty("value", "Sandra Gómez");
    await user.click(screen.getByRole("switch", { name: "Atiende citas" }));
    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ display_name: "Sandra Gómez", active: false });
  });

  it("no envía con el nombre vacío o de solo espacios", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre para mostrar"), "   ");
    await user.click(screen.getByRole("button", { name: "Crear profesional" }));

    expect(await screen.findByText("Escriba el nombre del profesional.")).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("solo lectura: campos deshabilitados y sin botón de guardar (gate)", async () => {
    await renderForm({ professional: professional("p1", "Sandra Gómez"), readOnly: true });

    expect(screen.getByLabelText("Nombre para mostrar")).toHaveProperty("disabled", true);
    expect(screen.queryByRole("button", { name: "Guardar cambios" })).toBeNull();
  });

  it("un 403 de la API se muestra como error del formulario", async () => {
    const { user } = await renderForm({
      onSubmit: vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido")),
      professional: professional("p1", "Sandra Gómez"),
    });

    await user.click(screen.getByRole("button", { name: "Guardar cambios" }));
    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });
});
