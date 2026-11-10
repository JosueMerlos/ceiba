import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ContextMenu, type ContextLevel } from "./context-menu";

const organization: ContextLevel = {
  key: "organization",
  label: "Organización",
  value: "o1",
  options: [
    { value: "o1", label: "Grupo Salud & Estilo" },
    { value: "o2", label: "Otra organización" },
  ],
};
const company: ContextLevel = {
  key: "company",
  label: "Empresa",
  value: "c1",
  options: [
    { value: "c1", label: "Clínica Dental Sonrisa" },
    { value: "c2", label: "Salón Estilo" },
  ],
};
const single = (key: ContextLevel["key"]): ContextLevel => ({
  key,
  label: key,
  value: "x",
  options: [{ value: "x", label: "Única opción" }],
});

const render_ = (levels: ContextLevel[], onSelect = vi.fn()) => {
  render(
    <ContextMenu
      triggerLabel="Cambiar el contexto de trabajo"
      summary="Clínica Dental Sonrisa"
      levels={levels}
      onSelect={onSelect}
    />,
  );
  return onSelect;
};

describe("ContextMenu (selector de contexto)", () => {
  it("criterio 1: se oculta por completo si solo hay una opción en cada nivel", () => {
    render_([single("organization"), single("company"), single("branch")]);

    expect(screen.queryByRole("button", { name: "Cambiar el contexto de trabajo" })).toBeNull();
  });

  it("se oculta si no hay niveles", () => {
    render_([]);

    expect(screen.queryByRole("button")).toBeNull();
  });

  it("solo muestra los niveles con más de una opción", async () => {
    render_([single("organization"), company]);

    await userEvent.click(screen.getByRole("button", { name: "Cambiar el contexto de trabajo" }));

    expect(await screen.findByText("Empresa")).toBeTruthy();
    expect(screen.queryByText("Organización")).toBeNull();
    expect(screen.getByRole("menuitemradio", { name: "Salón Estilo" })).toBeTruthy();
  });

  it("marca la opción actual y avisa del nivel y del valor elegidos", async () => {
    const onSelect = render_([organization, company]);

    await userEvent.click(screen.getByRole("button", { name: "Cambiar el contexto de trabajo" }));
    const current = await screen.findByRole("menuitemradio", { name: "Clínica Dental Sonrisa" });
    expect(current.getAttribute("aria-checked")).toBe("true");
    await userEvent.click(screen.getByRole("menuitemradio", { name: "Salón Estilo" }));

    expect(onSelect).toHaveBeenCalledWith("company", "c2");
  });

  it("el botón muestra dónde se está trabajando", () => {
    render_([company]);

    expect(
      screen.getByRole("button", { name: "Cambiar el contexto de trabajo" }).textContent,
    ).toContain("Clínica Dental Sonrisa");
  });
});
