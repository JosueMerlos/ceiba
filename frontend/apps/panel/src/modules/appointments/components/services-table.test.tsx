import { screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { service } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { ServicesTable } from "./services-table";

const corte = service("s1", "Corte clásico", { duration_minutes: 30, price_minor: 25000 });
const tinte = service("s2", "Tinte", { currency: "USD", price_minor: 4550, active: false });
const viejo = service("s3", "Peinado antiguo", {
  archived_at: "2026-11-01T10:00:00.000Z",
  active: false,
});

async function renderTable(props: Partial<React.ComponentProps<typeof ServicesTable>> = {}) {
  const handlers = { onSelect: vi.fn(), onArchive: vi.fn(), onRestore: vi.fn() };
  const view = await renderWithI18n(
    <ServicesTable
      services={[corte, tinte, viejo]}
      selectedId={null}
      canManage
      {...handlers}
      {...props}
    />,
  );
  return { ...handlers, ...view };
}

const row = (name: string) => screen.getByRole("row", { name: new RegExp(name) });

describe("ServicesTable", () => {
  it("muestra duración y precio con la moneda de CADA servicio (adversarial: no la de la empresa)", async () => {
    await renderTable();

    expect(within(row("Corte clásico")).getByText("30 min")).toBeTruthy();
    expect(within(row("Corte clásico")).getByText(/C\$\s?250\.00/)).toBeTruthy();
    expect(within(row("Tinte")).getByText(/US\$\s?45\.50/)).toBeTruthy();
  });

  it("distingue activo, pausado y archivado (un archivado no se lee como pausado)", async () => {
    await renderTable();

    expect(within(row("Corte clásico")).getByText("Activo")).toBeTruthy();
    expect(within(row("Tinte")).getByText("Pausado")).toBeTruthy();
    expect(within(row("Peinado antiguo")).getByText("Archivado")).toBeTruthy();
    expect(within(row("Peinado antiguo")).queryByText("Pausado")).toBeNull();
  });

  it("elegir un servicio avisa cuál y marca la fila seleccionada", async () => {
    const { user, onSelect } = await renderTable({ selectedId: "s2" });

    await user.click(screen.getByRole("button", { name: "Editar Corte clásico" }));

    expect(onSelect).toHaveBeenCalledWith("s1");
    expect(row("Tinte").getAttribute("aria-current")).toBe("true");
    expect(row("Corte clásico").getAttribute("aria-current")).toBeNull();
  });

  it("AC4: un archivado ofrece Restaurar, no Archivar; los demás, Archivar", async () => {
    const { user, onRestore, onArchive } = await renderTable();

    expect(within(row("Peinado antiguo")).queryByRole("button", { name: /Archivar/ })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Restaurar Peinado antiguo" }));
    expect(onRestore).toHaveBeenCalledWith(viejo);

    expect(within(row("Corte clásico")).queryByRole("button", { name: /Restaurar/ })).toBeNull();
    await user.click(screen.getByRole("button", { name: "Archivar Corte clásico" }));
    expect(onArchive).toHaveBeenCalledWith(corte);
  });

  it("sin permiso de gestionar no hay acciones de archivar ni restaurar", async () => {
    await renderTable({ canManage: false });

    expect(screen.queryByRole("button", { name: /Archivar|Restaurar/ })).toBeNull();
    expect(screen.queryByRole("columnheader", { name: "Acciones" })).toBeNull();
    expect(screen.getByRole("button", { name: "Editar Corte clásico" })).toBeTruthy();
  });
});
