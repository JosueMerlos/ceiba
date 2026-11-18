import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { branch, ids } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ProfessionalBranches } from "./professional-branches";

const branches = [
  branch(ids.branchA, ids.companyA, "Sucursal Centro"),
  branch(ids.branchA2, ids.companyA, "Sucursal Norte"),
];

describe("ProfessionalBranches", () => {
  it("marca las sucursales asignadas", async () => {
    await renderWithI18n(
      <ProfessionalBranches
        branches={branches}
        assignedIds={[ids.branchA]}
        canAssign
        onAssign={vi.fn()}
        onUnassign={vi.fn()}
      />,
    );
    expect(
      screen.getByRole("checkbox", { name: "Sucursal Centro" }).getAttribute("aria-checked"),
    ).toBe("true");
    expect(
      screen.getByRole("checkbox", { name: "Sucursal Norte" }).getAttribute("aria-checked"),
    ).toBe("false");
  });

  it("marcar una sucursal pide asignarla; desmarcar una asignada pide quitarla", async () => {
    const onAssign = vi.fn();
    const onUnassign = vi.fn();
    const { user } = await renderWithI18n(
      <ProfessionalBranches
        branches={branches}
        assignedIds={[ids.branchA]}
        canAssign
        onAssign={onAssign}
        onUnassign={onUnassign}
      />,
    );

    await user.click(screen.getByRole("checkbox", { name: "Sucursal Norte" }));
    expect(onAssign).toHaveBeenCalledWith(ids.branchA2);
    await user.click(screen.getByRole("checkbox", { name: "Sucursal Centro" }));
    expect(onUnassign).toHaveBeenCalledWith(ids.branchA);
  });

  it("sin permiso de asignar las casillas están deshabilitadas (gate)", async () => {
    const onAssign = vi.fn();
    const { user } = await renderWithI18n(
      <ProfessionalBranches
        branches={branches}
        assignedIds={[]}
        canAssign={false}
        onAssign={onAssign}
        onUnassign={vi.fn()}
      />,
    );
    const box = screen.getByRole("checkbox", { name: "Sucursal Centro" });
    expect(box).toHaveProperty("disabled", true);
    await user.click(box);
    expect(onAssign).not.toHaveBeenCalled();
  });

  it("sin sucursales visibles dice que no hay a dónde asignar", async () => {
    await renderWithI18n(
      <ProfessionalBranches
        branches={[]}
        assignedIds={[]}
        canAssign
        onAssign={vi.fn()}
        onUnassign={vi.fn()}
      />,
    );
    expect(screen.getByText("No hay sucursales disponibles para asignar.")).toBeTruthy();
  });
});
