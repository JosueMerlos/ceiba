import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { DurationField } from "../src";

const formatDuration = (minutes: number) => {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`;
};

function Harness({
  initial = 30,
  min,
  max,
  onChange,
}: {
  initial?: number;
  min?: number;
  max?: number;
  onChange?: (value: number) => void;
}) {
  const [value, setValue] = useState(initial);
  return (
    <DurationField
      aria-label="Duración"
      value={value}
      min={min}
      max={max}
      formatDuration={formatDuration}
      decreaseLabel="Quitar 5 minutos"
      increaseLabel="Agregar 5 minutos"
      presetsLabel="Duraciones frecuentes"
      onChange={(next) => {
        onChange?.(next);
        setValue(next);
      }}
    />
  );
}

const group = () => screen.getByRole("group", { name: "Duración" });
const shown = () => within(group()).getByRole("status").textContent;

describe("DurationField", () => {
  it("en 30, «+» dos veces y el atajo «90» deja 90", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Agregar 5 minutos" }));
    await user.click(screen.getByRole("button", { name: "Agregar 5 minutos" }));
    expect(shown()).toBe("40 min");

    await user.click(screen.getByRole("button", { name: "1 h 30 min" }));

    expect(onChange.mock.calls.map(([minutes]) => minutes)).toEqual([35, 40, 90]);
    expect(shown()).toBe("1 h 30 min");
    expect(
      screen.getByRole("button", { name: "1 h 30 min" }).getAttribute("aria-pressed"),
    ).toBe("true");
  });

  it("ofrece los atajos 15, 30, 45, 60 y 90 y marca el actual", () => {
    render(<Harness initial={45} />);

    const presets = within(screen.getByRole("group", { name: "Duraciones frecuentes" }))
      .getAllByRole("button")
      .map((button) => [button.textContent, button.getAttribute("aria-pressed")]);
    expect(presets).toEqual([
      ["15 min", "false"],
      ["30 min", "false"],
      ["45 min", "true"],
      ["1 h", "false"],
      ["1 h 30 min", "false"],
    ]);
  });

  it("nunca baja del mínimo: en el mínimo «−» está deshabilitado y no emite", async () => {
    const onChange = vi.fn();
    render(<Harness initial={10} min={10} onChange={onChange} />);
    const user = userEvent.setup();

    const decrease = screen.getByRole("button", { name: "Quitar 5 minutos" });
    expect(decrease).toHaveProperty("disabled", true);
    await user.click(decrease);

    expect(onChange).not.toHaveBeenCalled();
    expect(shown()).toBe("10 min");
  });

  it("cerca del mínimo «−» se detiene en el mínimo, no por debajo", async () => {
    const onChange = vi.fn();
    render(<Harness initial={12} min={10} onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Quitar 5 minutos" }));

    expect(onChange).toHaveBeenLastCalledWith(10);
  });

  it("un atajo por debajo del mínimo no se ofrece", () => {
    render(<Harness initial={30} min={20} />);

    expect(screen.queryByRole("button", { name: "15 min" })).toBeNull();
  });

  it("en el máximo «+» está deshabilitado", () => {
    render(<Harness initial={480} />);

    expect(screen.getByRole("button", { name: "Agregar 5 minutos" })).toHaveProperty(
      "disabled",
      true,
    );
  });
});
