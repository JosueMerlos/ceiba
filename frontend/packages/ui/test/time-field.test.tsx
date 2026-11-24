import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { TimeField } from "../src";

// The app passes the formatter from @ceiba/i18n; this one writes the same text by hand.
const formatClock = (clock: string) => {
  const [hours = 0, minutes = 0] = clock.split(":").map(Number);
  const suffix = hours < 12 ? "a. m." : "p. m.";
  return `${hours % 12 || 12}:${String(minutes).padStart(2, "0")} ${suffix}`;
};

function Harness({
  initial = "09:00",
  onChange,
  min,
  max,
}: {
  initial?: string;
  onChange?: (value: string) => void;
  min?: string;
  max?: string;
}) {
  const [value, setValue] = useState(initial);
  return (
    <>
      <TimeField
        aria-label="Desde"
        listLabel="Horas disponibles"
        value={value}
        min={min}
        max={max}
        formatClock={formatClock}
        onChange={(next) => {
          onChange?.(next);
          setValue(next);
        }}
      />
      <output data-testid="valor">{value}</output>
      <button type="button">Después</button>
    </>
  );
}

const field = () => screen.getByRole("combobox", { name: "Desde" });
const value = () => screen.getByTestId("valor").textContent;

describe("TimeField", () => {
  it("muestra la hora con el formato de la app", () => {
    render(<Harness initial="21:30" />);

    expect(field()).toHaveProperty("value", "9:30 p. m.");
  });

  it("escribir «930p» y salir del campo deja 21:30 y muestra «9:30 p. m.»", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);
    const user = userEvent.setup();

    await user.clear(field());
    await user.type(field(), "930p");
    await user.tab();

    expect(onChange).toHaveBeenLastCalledWith("21:30");
    expect(value()).toBe("21:30");
    expect(field()).toHaveProperty("value", "9:30 p. m.");
    expect(field().getAttribute("aria-invalid")).toBeNull();
  });

  it("Enter también confirma lo escrito", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.clear(field());
    await user.type(field(), "14{Enter}");

    expect(value()).toBe("14:00");
  });

  it("con flechas recorre la lista cada 15 min y Enter elige", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.click(field());
    await user.keyboard("{ArrowDown}{ArrowDown}");

    const list = screen.getByRole("listbox", { name: "Horas disponibles" });
    const active = document.getElementById(field().getAttribute("aria-activedescendant")!);
    expect(list.contains(active)).toBe(true);
    expect(active?.textContent).toContain("9:30 a. m.");
    expect(value()).toBe("09:00");

    await user.keyboard("{Enter}");

    expect(value()).toBe("09:30");
    expect(screen.queryByRole("listbox")).toBeNull();
  });

  it("la lista solo ofrece horas dentro de min y max", async () => {
    render(<Harness initial="10:00" min="08:00" max="09:00" />);
    const user = userEvent.setup();

    await user.click(field());
    await user.keyboard("{ArrowDown}");

    const options = screen.getAllByRole("option").map((option) => option.textContent);
    expect(options).toEqual(["8:00 a. m.", "8:15 a. m.", "8:30 a. m.", "8:45 a. m.", "9:00 a. m."]);
  });

  it("elegir una opción con el ratón la confirma", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.click(field());
    await user.keyboard("{ArrowDown}");
    await user.click(screen.getByRole("option", { name: "10:15 a. m." }));

    expect(value()).toBe("10:15");
  });

  it("lo inválido conserva el valor anterior y marca el campo", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);
    const user = userEvent.setup();

    await user.clear(field());
    await user.type(field(), "9:75");
    await user.tab();

    expect(onChange).not.toHaveBeenCalled();
    expect(value()).toBe("09:00");
    expect(field().getAttribute("aria-invalid")).toBe("true");
  });

  it("fuera de rango conserva el valor anterior y marca el campo", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} max="18:00" />);
    const user = userEvent.setup();

    await user.clear(field());
    await user.type(field(), "8p");
    await user.tab();

    expect(onChange).not.toHaveBeenCalled();
    expect(field().getAttribute("aria-invalid")).toBe("true");
  });

  it("acepta minutos escritos fuera del paso y hasta las 23:59", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.clear(field());
    await user.type(field(), "12:10{Enter}");
    expect(value()).toBe("12:10");

    await user.clear(field());
    await user.type(field(), "2359{Enter}");
    expect(value()).toBe("23:59");
    expect(field().getAttribute("aria-invalid")).toBeNull();
  });

  it("Escape cierra la lista sin cambiar el valor", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.click(field());
    await user.keyboard("{ArrowDown}{ArrowDown}{Escape}");

    expect(screen.queryByRole("listbox")).toBeNull();
    expect(value()).toBe("09:00");
    expect(field().getAttribute("aria-expanded")).toBe("false");
  });
});
