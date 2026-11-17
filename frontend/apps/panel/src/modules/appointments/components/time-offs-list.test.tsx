import { screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { timeOff } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { TimeOffsList } from "./time-offs-list";

const vacation = timeOff(
  "t1",
  { professionalId: "p1" },
  "2026-11-20T15:00:00.000Z",
  "2026-11-21T15:00:00.000Z",
  "Vacaciones",
);
const noReason = timeOff(
  "t2",
  { professionalId: "p1" },
  "2026-12-01T15:00:00.000Z",
  "2026-12-01T20:00:00.000Z",
);

describe("TimeOffsList", () => {
  it("muestra cada ausencia con su rango en la hora de la sucursal y el motivo cuando lo hay", async () => {
    await renderWithI18n(
      <TimeOffsList
        timeOffs={[vacation, noReason]}
        timeZone="America/Managua"
        canManage
        onDelete={vi.fn()}
      />,
    );

    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(within(items[0]!).getByText("Vacaciones")).toBeTruthy();
    expect(within(items[0]!).getByText(/9:00/)).toBeTruthy();
    expect(within(items[1]!).queryByText("Vacaciones")).toBeNull();
  });

  it("sin ausencias dice que no hay ninguna registrada", async () => {
    await renderWithI18n(
      <TimeOffsList timeOffs={[]} timeZone="America/Managua" canManage onDelete={vi.fn()} />,
    );
    expect(screen.getByText("No hay ausencias registradas.")).toBeTruthy();
    expect(screen.queryByRole("list")).toBeNull();
  });

  it("con permiso, Quitar entrega la ausencia elegida", async () => {
    const onDelete = vi.fn();
    const { user } = await renderWithI18n(
      <TimeOffsList
        timeOffs={[vacation, noReason]}
        timeZone="America/Managua"
        canManage
        onDelete={onDelete}
      />,
    );

    await user.click(screen.getAllByRole("button", { name: /^Quitar ausencia/ })[1]!);
    expect(onDelete).toHaveBeenCalledWith(noReason);
  });

  it("sin permiso no hay botones de quitar (gate)", async () => {
    await renderWithI18n(
      <TimeOffsList
        timeOffs={[vacation]}
        timeZone="America/Managua"
        canManage={false}
        onDelete={vi.fn()}
      />,
    );
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.getByText("Vacaciones")).toBeTruthy();
  });
});
