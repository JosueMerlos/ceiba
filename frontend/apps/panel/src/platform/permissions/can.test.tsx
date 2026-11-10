import { render, renderHook, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it } from "vitest";
import { meFixture } from "../../test/fixtures";
import { MeProvider } from "../me/me-provider";
import { Can, useCan } from "./can";

const withMe = (role: Parameters<typeof meFixture>[0] = {}) => {
  const me = meFixture(role).data;
  return ({ children }: { children: ReactNode }) => <MeProvider me={me}>{children}</MeProvider>;
};

describe("<Can>", () => {
  it("muestra el contenido cuando el usuario tiene el permiso", () => {
    render(
      <Can permission="appointments.appointment.create">
        <button type="button">Nueva cita</button>
      </Can>,
      { wrapper: withMe({ role: "receptionist" }) },
    );

    expect(screen.getByRole("button", { name: "Nueva cita" })).toBeTruthy();
  });

  it("lo oculta cuando falta el permiso", () => {
    render(
      <Can permission="appointments.service.manage">
        <button type="button">Gestionar servicios</button>
      </Can>,
      { wrapper: withMe({ role: "receptionist" }) },
    );

    expect(screen.queryByRole("button", { name: "Gestionar servicios" })).toBeNull();
  });

  it("muestra el fallback cuando falta el permiso", () => {
    render(
      <Can permission="appointments.service.manage" fallback={<p>Solo lectura</p>}>
        <button type="button">Gestionar servicios</button>
      </Can>,
      { wrapper: withMe({ role: "receptionist" }) },
    );

    expect(screen.getByText("Solo lectura")).toBeTruthy();
  });

  it("acepta varios permisos: basta con tener uno (any)", () => {
    render(
      <Can any={["appointments.service.manage", "appointments.appointment.read"]}>
        <p>Visible</p>
      </Can>,
      { wrapper: withMe({ role: "receptionist" }) },
    );

    expect(screen.getByText("Visible")).toBeTruthy();
  });

  it("con los módulos inactivos /me no trae permisos, así que todo queda oculto", () => {
    render(
      <Can permission="appointments.appointment.read">
        <p>Agenda</p>
      </Can>,
      { wrapper: withMe({ modules: [] }) },
    );

    expect(screen.queryByText("Agenda")).toBeNull();
  });
});

describe("useCan", () => {
  it("devuelve un predicado sobre los permisos de /me", () => {
    const { result } = renderHook(() => useCan(), { wrapper: withMe({ role: "professional" }) });

    expect(result.current("appointments.appointment.update_own")).toBe(true);
    expect(result.current("appointments.appointment.update")).toBe(false);
  });

  it("falla con un mensaje claro fuera de MeProvider", () => {
    expect(() => renderHook(() => useCan())).toThrow(/MeProvider/);
  });
});
