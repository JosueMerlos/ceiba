import { screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { service } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ProfessionalServices } from "./professional-services";

const catalog = [service("s1", "Corte clásico"), service("s2", "Barba"), service("s3", "Tinte")];

describe("ProfessionalServices", () => {
  it("marca los servicios que presta y guarda el conjunto completo tras cambiarlo", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { user } = await renderWithI18n(
      <ProfessionalServices services={catalog} selectedIds={["s1"]} canManage onSave={onSave} />,
    );

    expect(
      screen.getByRole("checkbox", { name: "Corte clásico" }).getAttribute("aria-checked"),
    ).toBe("true");
    await user.click(screen.getByRole("checkbox", { name: "Barba" }));
    await user.click(screen.getByRole("checkbox", { name: "Corte clásico" }));
    await user.click(screen.getByRole("button", { name: "Guardar servicios" }));

    expect(onSave).toHaveBeenCalledWith(["s2"]);
  });

  it("puede quitarlos todos: envía una lista vacía", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { user } = await renderWithI18n(
      <ProfessionalServices services={catalog} selectedIds={["s1"]} canManage onSave={onSave} />,
    );

    await user.click(screen.getByRole("checkbox", { name: "Corte clásico" }));
    await user.click(screen.getByRole("button", { name: "Guardar servicios" }));
    expect(onSave).toHaveBeenCalledWith([]);
  });

  it("sin permiso las casillas quedan deshabilitadas y no hay botón (gate)", async () => {
    await renderWithI18n(
      <ProfessionalServices
        services={catalog}
        selectedIds={["s2"]}
        canManage={false}
        onSave={vi.fn()}
      />,
    );

    expect(screen.getByRole("checkbox", { name: "Barba" })).toHaveProperty("disabled", true);
    expect(screen.queryByRole("button", { name: "Guardar servicios" })).toBeNull();
  });

  it("sin servicios en el catálogo guía a crearlos primero", async () => {
    await renderWithI18n(
      <ProfessionalServices services={[]} selectedIds={[]} canManage onSave={vi.fn()} />,
    );
    expect(screen.getByText(/Todavía no hay servicios activos/)).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Guardar servicios" })).toBeNull();
  });

  it("un servicio que presta pero ya no está en la lista (pausado) no se pierde al guardar", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { user } = await renderWithI18n(
      <ProfessionalServices
        services={catalog}
        selectedIds={["paused-1", "s1"]}
        canManage
        onSave={onSave}
      />,
    );

    await user.click(screen.getByRole("checkbox", { name: "Barba" }));
    await user.click(screen.getByRole("button", { name: "Guardar servicios" }));
    expect(onSave).toHaveBeenCalledWith(["paused-1", "s1", "s2"]);
  });
});
