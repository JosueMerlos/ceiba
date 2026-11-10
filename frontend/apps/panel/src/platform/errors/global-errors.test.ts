import { ApiError } from "@ceiba/api-client";
import { createI18n } from "@ceiba/i18n";
import { MutationObserver } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import { createQueryClient, describeError } from "./global-errors";

const problem = (status: number, code: string) => new ApiError(status, code, "Título del servidor");

async function setup() {
  const onUnauthorized = vi.fn();
  const notify = vi.fn();
  const queryClient = createQueryClient({ onUnauthorized, notify, retry: false });
  return { queryClient, onUnauthorized, notify };
}

const failQuery = (queryClient: ReturnType<typeof createQueryClient>, error: unknown) =>
  queryClient
    .fetchQuery({
      queryKey: ["x", Math.random()],
      queryFn: () => Promise.reject(error),
      retry: false,
    })
    .catch(() => undefined);

const failMutation = (
  queryClient: ReturnType<typeof createQueryClient>,
  error: unknown,
  meta?: Record<string, unknown>,
) =>
  new MutationObserver(queryClient, { mutationFn: () => Promise.reject(error), meta })
    .mutate()
    .catch(() => undefined);

describe("manejo global de errores de la API", () => {
  it("criterio 5: un 401 (sesión vencida) en una consulta avisa para ir al login", async () => {
    const { queryClient, onUnauthorized } = await setup();

    await failQuery(queryClient, problem(401, "auth.unauthenticated"));

    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("un 401 en una mutación también", async () => {
    const { queryClient, onUnauthorized } = await setup();

    await failMutation(queryClient, problem(401, "auth.unauthenticated"));

    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("credenciales inválidas NO son una sesión vencida: se muestran en el formulario", async () => {
    const { queryClient, onUnauthorized, notify } = await setup();

    await failMutation(queryClient, problem(401, "auth.invalid_credentials"), { silent: true });

    expect(onUnauthorized).not.toHaveBeenCalled();
    expect(notify).not.toHaveBeenCalled();
  });

  it("un 409 en una mutación avisa al usuario (refrescar y reintentar)", async () => {
    const { queryClient, notify } = await setup();
    const error = problem(409, "slot.unavailable");

    await failMutation(queryClient, error);

    expect(notify).toHaveBeenCalledWith(error);
  });

  it.each([403, 429, 500, 503])("un %i en una mutación avisa", async (status) => {
    const { queryClient, notify } = await setup();

    await failMutation(queryClient, problem(status, `http.${status}`));

    expect(notify).toHaveBeenCalledOnce();
  });

  it("un fallo de red en una mutación avisa", async () => {
    const { queryClient, notify } = await setup();

    await failMutation(queryClient, new TypeError("Failed to fetch"));

    expect(notify).toHaveBeenCalledOnce();
  });

  it("un 422 de una mutación lo maneja el formulario, no el aviso global", async () => {
    const { queryClient, notify } = await setup();

    await failMutation(queryClient, problem(422, "validation.failed"));

    expect(notify).not.toHaveBeenCalled();
  });

  it("las consultas con 403 y 404 lanzan al límite de error (pantalla de permiso / no encontrado)", async () => {
    const { queryClient } = await setup();
    const throwOnError = queryClient.getDefaultOptions().queries?.throwOnError;

    expect(typeof throwOnError).toBe("function");
    const decide = throwOnError as (error: Error) => boolean;
    expect(decide(problem(403, "access.denied"))).toBe(true);
    expect(decide(problem(404, "resource.not_found"))).toBe(true);
    expect(decide(problem(500, "http.500"))).toBe(false);
    expect(decide(problem(401, "auth.unauthenticated"))).toBe(false);
  });

  it("no reintenta errores 4xx (no van a cambiar) pero sí un fallo transitorio", () => {
    const queryClient = createQueryClient({ onUnauthorized: vi.fn(), notify: vi.fn() });
    const retry = queryClient.getDefaultOptions().queries?.retry as (
      count: number,
      error: Error,
    ) => boolean;

    expect(retry(0, problem(404, "resource.not_found"))).toBe(false);
    expect(retry(0, problem(503, "http.503"))).toBe(true);
    expect(retry(2, problem(503, "http.503"))).toBe(false);
  });
});

describe("describeError", () => {
  it("traduce por code (nunca por el message del servidor)", async () => {
    const { t } = await createI18n();

    expect(describeError(problem(401, "auth.invalid_credentials"), t)).toBe(
      "El correo o la contraseña no son correctos.",
    );
    expect(describeError(problem(409, "slot.unavailable"), t)).toBe(
      "El horario ya no está disponible. Elija otro.",
    );
  });

  it("sin traducción para el code, cae al mensaje del estado HTTP", async () => {
    const { t } = await createI18n();

    expect(describeError(problem(409, "otra.cosa"), t)).toMatch(/cambió mientras trabajaba/);
    expect(describeError(problem(500, "http.500"), t)).toMatch(/Ocurrió un problema/);
    expect(describeError(problem(403, "x"), t)).toMatch(/permiso|rol/i);
  });

  it("un fallo de red habla de la conexión", async () => {
    const { t } = await createI18n();

    expect(describeError(new TypeError("Failed to fetch"), t)).toMatch(/conexión/);
  });
});
