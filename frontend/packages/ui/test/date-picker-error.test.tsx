import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { DatePicker } from "../src";

// The calendar chunk fails the first time (a deploy replaced it, or the network dropped) and works on retry.
const attempts = vi.hoisted(() => ({ count: 0 }));
vi.mock("../src/components/calendar", () => ({
  default: () => {
    attempts.count += 1;
    if (attempts.count === 1) throw new Error("Failed to fetch dynamically imported module");
    return <div role="grid" aria-label="diciembre 2026" />;
  },
}));

describe("DatePicker si el calendario no carga", () => {
  it("muestra el aviso con Reintentar dentro del selector, sin tumbar la pantalla, y reintentar lo carga", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    render(
      <>
        <p>Resto de la pantalla</p>
        <DatePicker
          aria-label="Fecha"
          value="2026-12-14"
          onChange={() => {}}
          today="2026-12-10"
          formatDate={(day) => day}
          placeholder="Elegir fecha"
          calendarLabel="Calendario"
          previousMonthLabel="Mes anterior"
          nextMonthLabel="Mes siguiente"
          loadErrorLabel="No se pudo cargar el calendario."
          retryLabel="Reintentar"
        />
      </>,
    );
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Fecha" }));

    expect(await screen.findByText("No se pudo cargar el calendario.")).toBeTruthy();
    expect(screen.getByText("Resto de la pantalla")).toBeTruthy();

    await user.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByRole("grid", { name: "diciembre 2026" })).toBeTruthy();
  });
});
