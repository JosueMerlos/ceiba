import { ApiError } from "@ceiba/api-client";
import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ids, service, serviceOverride } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { BranchOverrideFields } from "./branch-override-fields";

const corte = service("s1", "Corte", { duration_minutes: 30, price_minor: 20000 });

async function renderFields(
  props: Partial<React.ComponentProps<typeof BranchOverrideFields>> = {},
) {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const onReset = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(
    <BranchOverrideFields
      service={corte}
      branchName="Sucursal Centro"
      canEditDuration
      canEditPrice
      onSubmit={onSubmit}
      onReset={onReset}
      {...props}
    />,
  );
  return { onSubmit, onReset, ...view };
}

describe("BranchOverrideFields", () => {
  it("AC2: con solo permiso de duración, la duración se edita y el precio es TEXTO sin input", async () => {
    const { user, onSubmit } = await renderFields({
      canEditPrice: false,
      override: serviceOverride("o1", "s1", ids.branchA, { price_minor: 25000 }),
    });

    expect(screen.queryByLabelText(/Precio en esta sucursal/)).toBeNull();
    expect(screen.queryByRole("textbox", { name: /Precio/ })).toBeNull();
    expect(screen.getByText(/250\.00/)).toBeTruthy();

    await user.type(screen.getByLabelText("Duración en esta sucursal (minutos)"), "45");
    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ duration_minutes: 45 });
  });

  it("envía SOLO las claves que el usuario cambió (adversarial: no reenvía el precio existente)", async () => {
    const { user, onSubmit } = await renderFields({
      override: serviceOverride("o1", "s1", ids.branchA, {
        duration_minutes: 40,
        price_minor: 25000,
      }),
    });

    await user.clear(screen.getByLabelText("Precio en esta sucursal (NIO)"));
    await user.type(screen.getByLabelText("Precio en esta sucursal (NIO)"), "260");
    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({ price_minor: 26000 });
  });

  it("vaciar un valor existente envía null explícito para quitarlo", async () => {
    const { user, onSubmit } = await renderFields({
      override: serviceOverride("o1", "s1", ids.branchA, {
        duration_minutes: 40,
        price_minor: 25000,
      }),
    });

    await user.clear(screen.getByLabelText("Duración en esta sucursal (minutos)"));
    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({ duration_minutes: null }));
  });

  it("sin cambios no llama a la API y lo dice", async () => {
    const { user, onSubmit } = await renderFields();

    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    expect(onSubmit).not.toHaveBeenCalled();
    expect(screen.getByText("No hay cambios que guardar.")).toBeTruthy();
  });

  it("AC2: el 403 de la API se muestra como error", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(403, "authz.forbidden", "Prohibido"));
    const { user } = await renderFields({ onSubmit });

    await user.type(screen.getByLabelText("Duración en esta sucursal (minutos)"), "45");
    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    expect((await screen.findByRole("alert")).textContent).toContain(
      "Su rol no incluye esta sección",
    );
  });

  it("rechaza una duración inválida sin llamar a la API", async () => {
    const { user, onSubmit } = await renderFields();

    await user.type(screen.getByLabelText("Duración en esta sucursal (minutos)"), "0");
    await user.click(screen.getByRole("button", { name: "Guardar para esta sucursal" }));

    expect(
      await screen.findByText("La duración debe ser un número entero de minutos, mayor que cero."),
    ).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("Quitar personalización solo aparece si hay override y llama a onReset", async () => {
    const { user, onReset } = await renderFields({
      override: serviceOverride("o1", "s1", ids.branchA, { duration_minutes: 40 }),
    });

    await user.click(screen.getByRole("button", { name: "Quitar personalización" }));

    expect(onReset).toHaveBeenCalledOnce();
  });

  it("sin ningún permiso de override todo es texto: sin inputs ni botones", async () => {
    await renderFields({ canEditDuration: false, canEditPrice: false });

    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByRole("spinbutton")).toBeNull();
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.getByText("30 min")).toBeTruthy();
  });
});
