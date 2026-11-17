import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { ContextPanel } from "../src";

function Harness({ initiallyOpen = false, footer }: { initiallyOpen?: boolean; footer?: boolean }) {
  const [open, setOpen] = useState(initiallyOpen);
  return (
    <div>
      <button type="button" onClick={() => setOpen(true)}>
        Editar servicio
      </button>
      <ContextPanel
        id="panel-servicio"
        open={open}
        onOpenChange={setOpen}
        title="Corte de cabello"
        closeLabel="Cerrar edición"
        footer={footer ? <button type="button">Guardar cambios</button> : undefined}
      >
        <label>
          Nombre
          <input defaultValue="Corte" />
        </label>
      </ContextPanel>
      <button type="button">Después del panel</button>
    </div>
  );
}

describe("ContextPanel", () => {
  it("abierto es un <aside> (complementary) con el título como nombre y el id dado", () => {
    render(<Harness initiallyOpen footer />);

    const panel = screen.getByRole("complementary", { name: "Corte de cabello" });
    expect(panel.id).toBe("panel-servicio");
    expect(within(panel).getByRole("heading", { name: "Corte de cabello" })).toBeTruthy();
    expect(within(panel).getByLabelText("Nombre")).toBeTruthy();
    expect(within(panel).getByRole("button", { name: "Guardar cambios" })).toBeTruthy();
  });

  it("cerrado no deja nada en el árbol (la hoja recupera el ancho)", () => {
    render(<Harness />);

    expect(screen.queryByRole("complementary")).toBeNull();
  });

  it("el botón de cierre lleva aria-expanded y aria-controls apuntando al id", () => {
    render(<Harness initiallyOpen />);

    const close = screen.getByRole("button", { name: "Cerrar edición" });
    expect(close.getAttribute("aria-expanded")).toBe("true");
    expect(close.getAttribute("aria-controls")).toBe("panel-servicio");
  });

  it("cerrar avisa con false y devuelve el foco al disparador", async () => {
    render(<Harness />);
    const user = userEvent.setup();
    const trigger = screen.getByRole("button", { name: "Editar servicio" });

    await user.click(trigger);
    await user.click(screen.getByRole("button", { name: "Cerrar edición" }));

    expect(screen.queryByRole("complementary")).toBeNull();
    expect(document.activeElement).toBe(trigger);
  });

  it("Escape dentro del panel lo cierra y devuelve el foco", async () => {
    render(<Harness />);
    const user = userEvent.setup();
    const trigger = screen.getByRole("button", { name: "Editar servicio" });

    await user.click(trigger);
    await user.click(screen.getByLabelText("Nombre"));
    await user.keyboard("{Escape}");

    expect(screen.queryByRole("complementary")).toBeNull();
    expect(document.activeElement).toBe(trigger);
  });

  it("no es modal: el foco por teclado sale del panel (no lo atrapa)", async () => {
    render(<Harness initiallyOpen footer />);
    const user = userEvent.setup();

    for (let step = 0; step < 6; step += 1) await user.tab();

    expect(document.activeElement).toBe(screen.getByRole("button", { name: "Después del panel" }));
    expect(screen.getByRole("complementary").getAttribute("aria-modal")).toBeNull();
  });

  it("si el disparador ya no existe al cerrar, no falla (adversarial)", async () => {
    const onOpenChange = vi.fn();
    const { rerender } = render(
      <ContextPanel id="p" open onOpenChange={onOpenChange} title="T" closeLabel="Cerrar">
        x
      </ContextPanel>,
    );
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Cerrar" }));

    expect(onOpenChange).toHaveBeenCalledWith(false);
    rerender(
      <ContextPanel id="p" open={false} onOpenChange={onOpenChange} title="T" closeLabel="Cerrar">
        x
      </ContextPanel>,
    );
    expect(screen.queryByRole("complementary")).toBeNull();
  });
});
