// UTC+14: if a civil date went through the browser's zone, the emitted day would shift.
process.env.TZ = "Pacific/Kiritimati";

import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { DatePicker, DateRangePicker, type DateRange } from "../src";

const formatDate = (day: string) => `día ${day}`;

const labels = {
  placeholder: "Elegir fecha",
  calendarLabel: "Calendario",
  previousMonthLabel: "Mes anterior",
  nextMonthLabel: "Mes siguiente",
  loadErrorLabel: "No se pudo cargar el calendario.",
  retryLabel: "Reintentar",
};

function SingleHarness({ onChange }: { onChange?: (day: string) => void }) {
  const [value, setValue] = useState("2026-12-14");
  return (
    <DatePicker
      aria-label="Fecha de la cita"
      value={value}
      today="2026-12-10"
      formatDate={formatDate}
      {...labels}
      onChange={(day) => {
        onChange?.(day);
        setValue(day);
      }}
    />
  );
}

function RangeHarness({ onChange }: { onChange?: (range: DateRange) => void }) {
  const [value, setValue] = useState<DateRange>({ from: null, to: null });
  return (
    <DateRangePicker
      aria-label="Ausencia"
      value={value}
      today="2026-12-10"
      formatDate={formatDate}
      {...labels}
      onChange={(range) => {
        onChange?.(range);
        setValue(range);
      }}
    />
  );
}

const trigger = (name: string) => screen.getByRole("button", { name: new RegExp(name) });
const day = (grid: HTMLElement, label: string) =>
  within(grid)
    .getAllByRole("button")
    .find((button) => button.textContent === label && !button.closest("[data-outside]"))!;

describe("DatePicker", () => {
  it("el disparador muestra la fecha con el formato de la app", () => {
    render(<SingleHarness />);

    expect(trigger("Fecha de la cita").textContent).toContain("día 2026-12-14");
  });

  it("al abrir carga el calendario de forma diferida y muestra el mes del valor", async () => {
    render(<SingleHarness />);
    const user = userEvent.setup();

    await user.click(trigger("Fecha de la cita"));

    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });
    expect(screen.getByRole("dialog", { name: "Calendario" }).contains(grid)).toBe(true);
    expect(grid.getAttribute("aria-label")?.toLowerCase()).toContain("diciembre 2026");
  });

  it("elegir un día emite la fecha civil yyyy-MM-dd sin que la zona del navegador la corra", async () => {
    const onChange = vi.fn();
    render(<SingleHarness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(trigger("Fecha de la cita"));
    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });
    await user.click(day(grid, "20"));

    expect(onChange).toHaveBeenCalledWith("2026-12-20");
    expect(screen.queryByRole("grid")).toBeNull();
    expect(trigger("Fecha de la cita").textContent).toContain("día 2026-12-20");
  });

  it("con teclado: la flecha mueve el foco un día y Enter lo elige", async () => {
    const onChange = vi.fn();
    render(<SingleHarness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(trigger("Fecha de la cita"));
    await screen.findByRole("grid", {}, { timeout: 5000 });
    await user.keyboard("{ArrowRight}{ArrowDown}{Enter}");

    expect(onChange).toHaveBeenCalledWith("2026-12-22");
  });

  it("marca hoy (de la sucursal) y el día elegido", async () => {
    render(<SingleHarness />);
    const user = userEvent.setup();

    await user.click(trigger("Fecha de la cita"));
    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });

    expect(day(grid, "10").closest("[data-today]")).not.toBeNull();
    expect(day(grid, "14").closest("[data-selected]")).not.toBeNull();
  });
});

describe("DateRangePicker", () => {
  it("primer clic inicio, segundo clic fin", async () => {
    const onChange = vi.fn();
    render(<RangeHarness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(trigger("Ausencia"));
    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });
    await user.click(day(grid, "14"));
    await user.click(day(grid, "18"));

    expect(onChange.mock.calls.map(([range]) => range)).toEqual([
      { from: "2026-12-14", to: null },
      { from: "2026-12-14", to: "2026-12-18" },
    ]);
  });

  it("rango invertido: un segundo clic anterior al inicio pasa a ser el nuevo inicio", async () => {
    const onChange = vi.fn();
    render(<RangeHarness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(trigger("Ausencia"));
    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });
    await user.click(day(grid, "18"));
    await user.click(day(grid, "14"));
    await user.click(day(grid, "16"));

    expect(onChange.mock.calls.map(([range]) => range)).toEqual([
      { from: "2026-12-18", to: null },
      { from: "2026-12-14", to: null },
      { from: "2026-12-14", to: "2026-12-16" },
    ]);
  });

  it("al completar el rango se cierra y, con uno completo, un clic empieza uno nuevo", async () => {
    const onChange = vi.fn();
    render(<RangeHarness onChange={onChange} />);
    const user = userEvent.setup();

    await user.click(trigger("Ausencia"));
    const grid = await screen.findByRole("grid", {}, { timeout: 5000 });
    await user.click(day(grid, "14"));
    await user.click(day(grid, "18"));
    expect(screen.queryByRole("grid")).toBeNull();

    await user.click(trigger("Ausencia"));
    await user.click(day(await screen.findByRole("grid"), "20"));

    expect(onChange).toHaveBeenLastCalledWith({ from: "2026-12-20", to: null });
  });
});
