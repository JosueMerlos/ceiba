import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAgendaDensity } from "./use-agenda-density";

const KEY = "ceiba.agenda-density.u1";

afterEach(() => {
  vi.restoreAllMocks();
  window.localStorage.clear();
});

describe("useAgendaDensity", () => {
  it("arranca cómoda si la persona nunca eligió", () => {
    const { result } = renderHook(() => useAgendaDensity("u1"));
    expect(result.current[0]).toBe("comfortable");
  });

  it("recuerda la elección por usuario", () => {
    const { result, unmount } = renderHook(() => useAgendaDensity("u1"));
    act(() => result.current[1]("compact"));
    expect(result.current[0]).toBe("compact");
    expect(window.localStorage.getItem(KEY)).toBe("compact");
    unmount();

    expect(renderHook(() => useAgendaDensity("u1")).result.current[0]).toBe("compact");
    expect(renderHook(() => useAgendaDensity("otra")).result.current[0]).toBe("comfortable");
  });

  it("un valor guardado desconocido se ignora", () => {
    window.localStorage.setItem(KEY, "gigante");
    expect(renderHook(() => useAgendaDensity("u1")).result.current[0]).toBe("comfortable");
  });

  it("si localStorage lanza, la densidad igual cambia en la sesión (adversarial)", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    const { result } = renderHook(() => useAgendaDensity("u1"));
    expect(result.current[0]).toBe("comfortable");
    act(() => result.current[1]("compact"));
    expect(result.current[0]).toBe("compact");
  });
});
