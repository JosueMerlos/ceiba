import { ApiError } from "@ceiba/api-client";
import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { resource } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ResourceForm } from "./resource-form";

// The form has no button of its own: the modal's footer submits it through `form={id}`.
async function renderForm(props: Partial<React.ComponentProps<typeof ResourceForm>> = {}) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(
    <>
      <ResourceForm id="resource-form" onSubmit={onSubmit} {...props} />
      <button type="submit" form="resource-form">
        Enviar
      </button>
    </>,
  );
  return { onSubmit, ...view };
}

describe("ResourceForm", () => {
  it("crea: sillón por defecto, nombre recortado y activo", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), " Sillón 1 ");
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ name: "Sillón 1", kind: "chair", active: true });
  });

  it("el tipo sale del enum del contrato: sillón, sala y equipo", async () => {
    const { user, onSubmit } = await renderForm();

    await user.type(screen.getByLabelText("Nombre"), "Sala de color");
    await user.click(screen.getByRole("combobox", { name: "Tipo" }));
    expect(screen.getAllByRole("option").map((option) => option.textContent)).toEqual([
      "Sillón",
      "Sala",
      "Equipo",
    ]);
    await user.click(screen.getByRole("option", { name: "Sala" }));
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit.mock.calls[0]![0]).toMatchObject({ kind: "room" });
  });

  it("edita: precarga el recurso y guarda el estado nuevo", async () => {
    const { user, onSubmit } = await renderForm({
      resource: resource("r1", "Camilla 2", { kind: "equipment" }),
    });

    expect(screen.getByLabelText("Nombre")).toHaveProperty("value", "Camilla 2");
    expect(screen.getByRole("combobox", { name: "Tipo" }).textContent).toBe("Equipo");
    await user.click(screen.getByRole("switch", { name: "Disponible" }));
    await user.click(screen.getByRole("button", { name: "Enviar" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ name: "Camilla 2", kind: "equipment", active: false });
  });

  it("no envía sin nombre y muestra el 403 de la API como error del formulario", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido"));
    const { user } = await renderForm({ onSubmit });

    await user.click(screen.getByRole("button", { name: "Enviar" }));
    expect(await screen.findByText("Escriba el nombre del recurso.")).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();

    await user.type(screen.getByLabelText("Nombre"), "Sillón 3");
    await user.click(screen.getByRole("button", { name: "Enviar" }));
    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });

  it("avisa si hay cambios sin guardar y deja de avisar al volver al valor inicial", async () => {
    const onDirtyChange = vi.fn();
    const { user } = await renderForm({ resource: resource("r1", "Sillón 1"), onDirtyChange });

    await user.type(screen.getByLabelText("Nombre"), "0");
    expect(onDirtyChange).toHaveBeenLastCalledWith(true);
    await user.type(screen.getByLabelText("Nombre"), "{Backspace}");
    expect(onDirtyChange).toHaveBeenLastCalledWith(false);
  });
});
