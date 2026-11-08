import { describe, expect, test } from "vitest";
import { ApiError, isApiError } from "../src";

const problemResponse = (body: unknown, status: number, contentType = "application/problem+json") =>
  new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "Content-Type": contentType },
  });

describe("ApiError.fromResponse", () => {
  test("traduce un problem+json a un error tipado con status, code, errors y request_id", async () => {
    const response = problemResponse(
      {
        type: "urn:ceiba:error:validation.failed",
        title: "Los datos no son válidos",
        status: 422,
        code: "validation.failed",
        instance: "/api/v1/x",
        request_id: "req-1",
        errors: [{ field: "name", code: "blank", message: "no puede estar en blanco" }],
      },
      422,
    );

    const error = await ApiError.fromResponse(response);

    expect(error).toBeInstanceOf(Error);
    expect(error).toMatchObject({
      name: "ApiError",
      status: 422,
      code: "validation.failed",
      title: "Los datos no son válidos",
      requestId: "req-1",
      errors: [{ field: "name", code: "blank", message: "no puede estar en blanco" }],
    });
    expect(error.message).toBe("Los datos no son válidos");
  });

  test("sin errores por campo, errors es un arreglo vacío (nunca undefined)", async () => {
    const error = await ApiError.fromResponse(
      problemResponse(
        {
          type: "t",
          title: "No se encontró",
          status: 404,
          code: "resource.not_found",
          instance: "/x",
          request_id: "r",
        },
        404,
      ),
    );

    expect(error.errors).toEqual([]);
    expect(error.detail).toBeUndefined();
  });

  test("una respuesta que no es problem+json (p. ej. un 502 del proxy) se convierte en http.<status>", async () => {
    const error = await ApiError.fromResponse(
      problemResponse("<html>Bad gateway</html>", 502, "text/html"),
    );

    expect(error).toMatchObject({
      status: 502,
      code: "http.502",
      errors: [],
      requestId: undefined,
    });
  });

  test("un cuerpo problem+json corrupto o con otra forma tampoco rompe", async () => {
    const broken = await ApiError.fromResponse(problemResponse("{no es json", 500));
    const other = await ApiError.fromResponse(problemResponse({ foo: "bar" }, 500));

    expect(broken.code).toBe("http.500");
    expect(other.code).toBe("http.500");
  });

  test("isApiError distingue ApiError de otros errores", async () => {
    const error = await ApiError.fromResponse(problemResponse("x", 500, "text/plain"));

    expect(isApiError(error)).toBe(true);
    expect(isApiError(new Error("x"))).toBe(false);
    expect(isApiError("x")).toBe(false);
  });
});
