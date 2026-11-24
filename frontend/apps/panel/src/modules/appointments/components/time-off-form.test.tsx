import { ApiError } from "@ceiba/api-client";
import { formatClock, formatPlainDate } from "@ceiba/i18n";
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import type { UserEvent } from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { fillWallClock } from "../../../test/date-time-fields";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { TimeOffForm } from "./time-off-form";

async function renderForm(timeZone = "America/Managua") {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(<TimeOffForm timeZone={timeZone} onSubmit={onSubmit} />);
  return { onSubmit, ...view };
}

const fill = (user: UserEvent, legend: string, value: string) =>
  fillWallClock(user, document.body, legend, value);

describe("TimeOffForm", () => {
  it("convierte la hora local de la sucursal a UTC antes de enviar", async () => {
    const { user, onSubmit } = await renderForm("America/Managua");

    await fill(user, "Desde", "2026-11-20T09:00");
    await fill(user, "Hasta", "2026-11-20T17:30");
    await user.type(screen.getByLabelText("Motivo (opcional)"), "Trámite personal");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit).toHaveBeenCalledWith({
      starts_at: "2026-11-20T15:00:00.000Z",
      ends_at: "2026-11-20T23:30:00.000Z",
      reason: "Trámite personal",
    });
  });

  it("la zona de la sucursal manda: la misma hora local en Bogotá da otro instante UTC", async () => {
    const { user, onSubmit } = await renderForm("America/Bogota");

    await fill(user, "Desde", "2026-11-20T09:00");
    await fill(user, "Hasta", "2026-11-20T10:00");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    expect(onSubmit.mock.calls[0]![0]).toEqual({
      starts_at: "2026-11-20T14:00:00.000Z",
      ends_at: "2026-11-20T15:00:00.000Z",
      reason: null,
    });
    expect(screen.getByText(/America\/Bogota/)).toBeTruthy();
  });

  it("avisa de no registrar datos de salud en el motivo", async () => {
    await renderForm();
    expect(screen.getByText(/No registre datos de salud/)).toBeTruthy();
  });

  it("no envía si falta una fecha, si el fin no es posterior al inicio o si el motivo pasa de 200 caracteres", async () => {
    const { user, onSubmit } = await renderForm();

    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));
    expect(await screen.findByText("Escriba cuándo empieza.")).toBeTruthy();
    // The error is announced on the controls themselves and focus lands on the first invalid one.
    const start = within(screen.getByRole("group", { name: "Desde" }));
    const startDate = start.getByRole("button", { name: "Fecha" });
    expect(document.activeElement).toBe(startDate);
    for (const control of [startDate, start.getByRole("combobox", { name: "Hora" })]) {
      const described = (control.getAttribute("aria-describedby") ?? "")
        .split(" ")
        .map((id) => document.getElementById(id)?.textContent);
      expect(described).toContain("Escriba cuándo empieza.");
    }
    expect(screen.getByText("Escriba cuándo termina.")).toBeTruthy();

    await fill(user, "Desde", "2026-11-20T10:00");
    await fill(user, "Hasta", "2026-11-20T09:00");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));
    expect(await screen.findByText("El fin debe ser posterior al inicio.")).toBeTruthy();

    await fill(user, "Hasta", "2026-11-20T11:00");
    fireEvent.change(screen.getByLabelText("Motivo (opcional)"), {
      target: { value: "x".repeat(201) },
    });
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));
    expect(await screen.findByText("El motivo admite hasta 200 caracteres.")).toBeTruthy();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("un 422 de la API se muestra en el formulario y los datos se conservan", async () => {
    const onSubmit = vi
      .fn()
      .mockRejectedValue(
        new ApiError(422, "validation.failed", "Datos inválidos", [
          { field: "ends_at", code: "invalid", message: "Dura más de 366 días" },
        ]),
      );
    const { user } = await renderWithI18n(
      <TimeOffForm timeZone="America/Managua" onSubmit={onSubmit} />,
    );

    await fill(user, "Desde", "2026-11-20T09:00");
    await fill(user, "Hasta", "2026-12-20T09:00");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));

    expect(await screen.findByText("Dura más de 366 días")).toBeTruthy();
    const start = screen.getByRole("group", { name: "Desde" });
    expect(within(start).getByRole("button", { name: "Fecha" }).textContent).toContain(
      formatPlainDate("2026-11-20"),
    );
    expect(within(start).getByRole("combobox", { name: "Hora" })).toHaveProperty(
      "value",
      formatClock("09:00"),
    );
  });

  it("fecha y hora salen de los campos propios: ningún input nativo de fecha u hora", async () => {
    const { container } = await renderForm();

    expect(
      container.querySelectorAll("input[type=date], input[type=time], input[type=datetime-local]"),
    ).toHaveLength(0);
  });

  it("dentro de un modal (formId) no pinta su botón: el pie lo envía, y avisa si tiene datos", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    const onDirtyChange = vi.fn();
    const { user } = await renderWithI18n(
      <>
        <TimeOffForm
          timeZone="America/Managua"
          formId="time-off"
          onDirtyChange={onDirtyChange}
          onSubmit={onSubmit}
        />
        <button type="submit" form="time-off">
          Pie del modal
        </button>
      </>,
    );

    expect(screen.queryByRole("button", { name: "Agregar ausencia" })).toBeNull();
    await fill(user, "Desde", "2026-11-20T09:00");
    expect(onDirtyChange).toHaveBeenLastCalledWith(true);
    await fill(user, "Hasta", "2026-11-20T10:00");
    await user.click(screen.getByRole("button", { name: "Pie del modal" }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledOnce());
    await waitFor(() => expect(onDirtyChange).toHaveBeenLastCalledWith(false));
  });
});
