import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { TimeRangeField, type TimeRange } from "../src";

const formatClock = (clock: string) => {
  const [hours = 0, minutes = 0] = clock.split(":").map(Number);
  return `${hours % 12 || 12}:${String(minutes).padStart(2, "0")} ${hours < 12 ? "a. m." : "p. m."}`;
};

function Harness({ onChange }: { onChange?: (range: TimeRange) => void }) {
  const [value, setValue] = useState<TimeRange>({ start: "09:00", end: "13:00" });
  return (
    <TimeRangeField
      aria-label="Franja del lunes"
      value={value}
      startLabel="Desde"
      endLabel="Hasta"
      listLabel="Horas"
      formatClock={formatClock}
      onChange={(range) => {
        onChange?.(range);
        setValue(range);
      }}
    />
  );
}

describe("TimeRangeField", () => {
  it("es un grupo con dos horas, Desde y Hasta, en el formato de la app", () => {
    render(<Harness />);

    const group = screen.getByRole("group", { name: "Franja del lunes" });
    expect(within(group).getByRole("combobox", { name: "Desde" })).toHaveProperty(
      "value",
      "9:00 a. m.",
    );
    expect(within(group).getByRole("combobox", { name: "Hasta" })).toHaveProperty(
      "value",
      "1:00 p. m.",
    );
  });

  it("cambiar un extremo emite el rango completo y conserva el otro", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);
    const user = userEvent.setup();

    const end = screen.getByRole("combobox", { name: "Hasta" });
    await user.clear(end);
    await user.type(end, "2p");
    await user.tab();

    expect(onChange).toHaveBeenLastCalledWith({ start: "09:00", end: "14:00" });
  });

  it("no corrige un rango invertido: lo deja a la validación del formulario", async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);
    const user = userEvent.setup();

    const start = screen.getByRole("combobox", { name: "Desde" });
    await user.clear(start);
    await user.type(start, "14");
    await user.tab();

    expect(onChange).toHaveBeenLastCalledWith({ start: "14:00", end: "13:00" });
  });

  it("sin nombre propio no crea un grupo vacío y aplica fieldClassName a cada hora", () => {
    render(
      <div role="group" aria-label="Lunes">
        <TimeRangeField
          value={{ start: "09:00", end: "13:00" }}
          startLabel="Inicio"
          endLabel="Fin"
          listLabel="Horas"
          formatClock={formatClock}
          fieldClassName="sm:w-36"
          onChange={() => {}}
        />
      </div>,
    );

    expect(screen.getAllByRole("group").map((group) => group.getAttribute("aria-label"))).toEqual([
      "Lunes",
    ]);
    const start = screen.getByRole("combobox", { name: "Inicio" });
    expect(start.closest("[data-slot='time-field']")!.className).toContain("sm:w-36");
  });
});
