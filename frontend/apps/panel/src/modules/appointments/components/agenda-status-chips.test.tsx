import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { renderWithI18n } from "../../../test/render-with-i18n";
import type { StatusTone } from "../lib/agenda-status";
import { AgendaStatusChips } from "./agenda-status-chips";

const counts: Record<StatusTone, number> = {
  pending: 2,
  confirmed: 3,
  arrived: 1,
  done: 4,
  missed: 0,
};

const chip = (name: RegExp) => screen.getByRole("button", { name });

describe("AgendaStatusChips", () => {
  it("es la leyenda: un chip por estado con su contador y «Todas» con las visibles", async () => {
    await renderWithI18n(
      <AgendaStatusChips
        counts={counts}
        hidden={new Set()}
        onToggle={vi.fn()}
        onShowAll={vi.fn()}
      />,
    );

    expect(screen.getByRole("group", { name: "Filtrar por estado" })).toBeTruthy();
    expect(chip(/^Todas/).textContent).toContain("10");
    expect(chip(/^Por confirmar/).textContent).toContain("2");
    expect(chip(/^Completada/).textContent).toContain("4");
    for (const name of [/^Todas/, /^Confirmada/, /^Llegó/, /^No asistió/]) {
      expect(chip(name).getAttribute("aria-pressed")).toBe("true");
    }
  });

  it("un estado oculto queda sin marcar y «Todas» cuenta solo lo visible", async () => {
    await renderWithI18n(
      <AgendaStatusChips
        counts={counts}
        hidden={new Set<StatusTone>(["done"])}
        onToggle={vi.fn()}
        onShowAll={vi.fn()}
      />,
    );

    expect(chip(/^Completada/).getAttribute("aria-pressed")).toBe("false");
    expect(chip(/^Todas/).getAttribute("aria-pressed")).toBe("false");
    expect(chip(/^Todas/).textContent).toContain("6");
  });

  it("tocar un chip avisa su estado y «Todas» lo muestra todo", async () => {
    const onToggle = vi.fn();
    const onShowAll = vi.fn();
    await renderWithI18n(
      <AgendaStatusChips
        counts={counts}
        hidden={new Set<StatusTone>(["done"])}
        onToggle={onToggle}
        onShowAll={onShowAll}
      />,
    );

    await userEvent.click(chip(/^Completada/));
    expect(onToggle).toHaveBeenCalledWith("done");
    await userEvent.click(chip(/^Todas/));
    expect(onShowAll).toHaveBeenCalledOnce();
  });
});
