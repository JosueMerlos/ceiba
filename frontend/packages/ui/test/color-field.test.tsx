import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it } from "vitest";
import { ColorField } from "../src";

function Controlled({ initial = "" }: { initial?: string }) {
  const [value, setValue] = useState(initial);
  return (
    <ColorField
      aria-label="Color principal"
      pickerLabel="Selector"
      value={value}
      onValueChange={setValue}
    />
  );
}

describe("ColorField", () => {
  it("el campo de texto muestra y edita el valor hexadecimal", async () => {
    render(<Controlled initial="#1D6C4E" />);
    const hex = screen.getByLabelText("Color principal") as HTMLInputElement;
    expect(hex.value).toBe("#1D6C4E");

    await userEvent.clear(hex);
    await userEvent.type(hex, "#FFFF00");

    expect(hex.value).toBe("#FFFF00");
  });

  it("el selector nativo refleja un hex válido y escribe en el mismo valor", () => {
    render(<Controlled initial="#1D6C4E" />);
    const picker = screen.getByLabelText("Selector") as HTMLInputElement;
    expect(picker.type).toBe("color");
    expect(picker.value).toBe("#1d6c4e");

    fireEvent.change(picker, { target: { value: "#ffff00" } });

    expect((screen.getByLabelText("Color principal") as HTMLInputElement).value).toBe("#FFFF00");
  });

  it("adversarial: con un texto que no es hex el selector no lo recibe como valor", () => {
    render(<Controlled initial="rojo" />);

    expect((screen.getByLabelText("Selector") as HTMLInputElement).value).toBe("#000000");
    expect((screen.getByLabelText("Color principal") as HTMLInputElement).value).toBe("rojo");
  });
});
