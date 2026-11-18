import { ApiError } from "@ceiba/api-client";
import { describe, expect, it, vi } from "vitest";
import { applyApiErrors } from "./apply-api-errors";

const unprocessable = (errors: { field: string; code?: string; message: string }[]) =>
  new ApiError(
    422,
    "validation.failed",
    "Datos inválidos",
    errors.map(({ code = "invalid", ...rest }) => ({ code, ...rest })),
  );

describe("applyApiErrors", () => {
  it("un campo conocido va a su campo con el mensaje de la API", () => {
    const setError = vi.fn();

    const handled = applyApiErrors(
      unprocessable([{ field: "name", message: "no puede estar en blanco" }]),
      setError,
    );

    expect(handled).toBe(true);
    expect(setError).toHaveBeenCalledTimes(1);
    expect(setError).toHaveBeenCalledWith(
      "name",
      expect.objectContaining({ message: "no puede estar en blanco" }),
    );
  });

  it("base va a root.serverError", () => {
    const setError = vi.fn();

    applyApiErrors(unprocessable([{ field: "base", message: "ya existe una cita" }]), setError);

    expect(setError).toHaveBeenCalledWith(
      "root.serverError",
      expect.objectContaining({ message: "ya existe una cita" }),
    );
  });

  it("un campo que el formulario no conoce va a root.serverError cuando se da fieldMap", () => {
    const setError = vi.fn();

    applyApiErrors(unprocessable([{ field: "desconocido", message: "no válido" }]), setError, {
      duration_minutes: "durationMinutes",
    });

    expect(setError).toHaveBeenCalledWith(
      "root.serverError",
      expect.objectContaining({ message: "no válido" }),
    );
  });

  it("fieldMap traduce el nombre de la API al del formulario", () => {
    const setError = vi.fn();

    applyApiErrors(
      unprocessable([{ field: "duration_minutes", message: "debe ser mayor que 0" }]),
      setError,
      { duration_minutes: "durationMinutes" },
    );

    expect(setError).toHaveBeenCalledWith(
      "durationMinutes",
      expect.objectContaining({ message: "debe ser mayor que 0" }),
    );
  });

  it("varios errores se reparten, y el primero de cada campo gana", () => {
    const setError = vi.fn();

    applyApiErrors(
      unprocessable([
        { field: "name", message: "primero" },
        { field: "name", message: "segundo" },
        { field: "base", message: "general" },
      ]),
      setError,
    );

    expect(setError).toHaveBeenCalledTimes(2);
    expect(setError).toHaveBeenCalledWith("name", expect.objectContaining({ message: "primero" }));
  });

  it("un 422 sin errores por campo va a root.serverError con el título", () => {
    const setError = vi.fn();

    const handled = applyApiErrors(unprocessable([]), setError);

    expect(handled).toBe(true);
    expect(setError).toHaveBeenCalledWith(
      "root.serverError",
      expect.objectContaining({ message: "Datos inválidos" }),
    );
  });

  it("un error que no es 422 no toca el formulario (adversarial)", () => {
    const setError = vi.fn();

    const handled = applyApiErrors(new ApiError(403, "access.denied", "Sin permiso"), setError);

    expect(handled).toBe(false);
    expect(setError).not.toHaveBeenCalled();
  });

  it("un fallo de red (no ApiError) tampoco lo toca (adversarial)", () => {
    const setError = vi.fn();

    expect(applyApiErrors(new TypeError("Failed to fetch"), setError)).toBe(false);
    expect(applyApiErrors(undefined, setError)).toBe(false);
    expect(setError).not.toHaveBeenCalled();
  });
});
