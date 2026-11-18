import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { FileDrop } from "../src";

const labels = {
  chooseLabel: "Elegir imagen",
  replaceLabel: "Cambiar imagen",
  removeLabel: "Quitar logo",
  previewAlt: "Vista previa del logo",
  emptyLabel: "Sin imagen",
};
const png = new File([new Uint8Array([1])], "logo.png", { type: "image/png" });

describe("FileDrop", () => {
  it("sin imagen ofrece elegir y no ofrece quitar", () => {
    render(
      <FileDrop
        id="f"
        accept="image/png"
        previewUrl={null}
        onSelect={vi.fn()}
        onRemove={vi.fn()}
        {...labels}
      />,
    );

    expect(screen.getByText("Elegir imagen")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Quitar logo" })).toBeNull();
  });

  it("al elegir un archivo avisa con el File", async () => {
    const onSelect = vi.fn();
    render(
      <FileDrop
        id="f"
        accept="image/png"
        previewUrl={null}
        onSelect={onSelect}
        onRemove={vi.fn()}
        {...labels}
      />,
    );

    await userEvent.upload(screen.getByLabelText("Elegir imagen"), png);

    expect(onSelect).toHaveBeenCalledWith(png);
  });

  it("con imagen muestra la vista previa, ofrece cambiar y quitar", async () => {
    const onRemove = vi.fn();
    render(
      <FileDrop
        id="f"
        accept="image/png"
        previewUrl="blob:x"
        onSelect={vi.fn()}
        onRemove={onRemove}
        {...labels}
      />,
    );

    expect((screen.getByAltText("Vista previa del logo") as HTMLImageElement).src).toContain(
      "blob:x",
    );
    expect(screen.getByText("Cambiar imagen")).toBeTruthy();
    await userEvent.click(screen.getByRole("button", { name: "Quitar logo" }));

    expect(onRemove).toHaveBeenCalledOnce();
  });

  it("adversarial: se puede volver a elegir el mismo archivo tras quitarlo", async () => {
    const onSelect = vi.fn();
    render(
      <FileDrop
        id="f"
        accept="image/png"
        previewUrl={null}
        onSelect={onSelect}
        onRemove={vi.fn()}
        {...labels}
      />,
    );
    const input = screen.getByLabelText("Elegir imagen");

    await userEvent.upload(input, png);
    await userEvent.upload(input, png);

    expect(onSelect).toHaveBeenCalledTimes(2);
  });
});
