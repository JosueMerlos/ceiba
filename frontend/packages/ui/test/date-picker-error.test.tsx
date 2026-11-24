import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { DatePicker } from "../src";

// The calendar chunk cannot be downloaded at first (a deploy replaced it, the network dropped): the dynamic import
// itself rejects, which React.lazy remembers; after the retry the download works.
const chunk = vi.hoisted(() => ({ broken: true }));
vi.mock("../src/components/calendar", () => {
  if (chunk.broken) throw new Error("Failed to fetch dynamically imported module");
  return { default: () => <div role="grid" aria-label="diciembre 2026" /> };
});

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

    chunk.broken = false;
    await user.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByRole("grid", { name: "diciembre 2026" })).toBeTruthy();
  });
});
