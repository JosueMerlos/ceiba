import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { EmptyState } from "./empty-state";

describe("EmptyState", () => {
  it("muestra título, guía y la acción", async () => {
    const onAction = vi.fn();
    const { user } = await renderWithI18n(
      <EmptyState
        title="Agregue su primer servicio"
        description="Los servicios son lo que sus clientes reservan."
        action={{ label: "Agregar servicio", onClick: onAction }}
      />,
    );

    expect(screen.getByRole("heading", { name: "Agregue su primer servicio" })).toBeTruthy();
    expect(screen.getByText("Los servicios son lo que sus clientes reservan.")).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Agregar servicio" }));
    expect(onAction).toHaveBeenCalledOnce();
  });

  it("sin acción no dibuja ningún botón (el gate lo decide quien lo usa)", async () => {
    await renderWithI18n(<EmptyState title="Sin servicios" description="Guía" />);

    expect(screen.queryByRole("button")).toBeNull();
  });

  it("admite contenido adicional bajo la guía", async () => {
    await renderWithI18n(
      <EmptyState title="T" description="D">
        <p>Elija una sucursal</p>
      </EmptyState>,
    );

    expect(screen.getByText("Elija una sucursal")).toBeTruthy();
  });
});
