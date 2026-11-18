import { ApiError } from "@ceiba/api-client";
import { fireEvent, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { TimeOffForm } from "./time-off-form";

async function renderForm(timeZone = "America/Managua") {
  const onSubmit = vi.fn().mockResolvedValue(undefined);
  const view = await renderWithI18n(<TimeOffForm timeZone={timeZone} onSubmit={onSubmit} />);
  return { onSubmit, ...view };
}

const fill = (label: string, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } });

describe("TimeOffForm", () => {
  it("convierte la hora local de la sucursal a UTC antes de enviar", async () => {
    const { user, onSubmit } = await renderForm("America/Managua");

    fill("Desde", "2026-11-20T09:00");
    fill("Hasta", "2026-11-20T17:30");
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

    fill("Desde", "2026-11-20T09:00");
    fill("Hasta", "2026-11-20T10:00");
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
    expect(screen.getByText("Escriba cuándo termina.")).toBeTruthy();

    fill("Desde", "2026-11-20T10:00");
    fill("Hasta", "2026-11-20T09:00");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));
    expect(await screen.findByText("El fin debe ser posterior al inicio.")).toBeTruthy();

    fill("Hasta", "2026-11-20T11:00");
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

    fill("Desde", "2026-11-20T09:00");
    fill("Hasta", "2028-11-20T09:00");
    await user.click(screen.getByRole("button", { name: "Agregar ausencia" }));

    expect(await screen.findByText("Dura más de 366 días")).toBeTruthy();
    expect(screen.getByLabelText("Desde")).toHaveProperty("value", "2026-11-20T09:00");
  });
});
