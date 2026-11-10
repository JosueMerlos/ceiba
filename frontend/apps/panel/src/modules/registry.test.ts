import { describe, expect, it } from "vitest";
import { meFixture } from "../test/fixtures";
import { activeModules, navigationFor } from "./registry";

describe("registro de módulos del front", () => {
  it("monta solo los módulos activos según /me", () => {
    const withAppointments = meFixture({ modules: ["appointments"] }).data;
    const without = meFixture({ modules: [] }).data;

    expect(activeModules(withAppointments).map((module) => module.key)).toEqual(["appointments"]);
    expect(activeModules(without)).toEqual([]);
  });

  it("ignora módulos activos en el backend que este front no conoce", () => {
    const me = meFixture({ modules: ["appointments", "inventario"] }).data;

    expect(activeModules(me).map((module) => module.key)).toEqual(["appointments"]);
  });

  it("criterio 3: con appointments inactivo no hay ítems de navegación ni rutas", () => {
    const me = meFixture({ modules: [] }).data;

    expect(navigationFor(me)).toEqual([]);
    expect(activeModules(me).flatMap((module) => module.routes)).toEqual([]);
  });

  it("criterio 4: un receptionist solo ve los ítems cuyo permiso tiene", () => {
    const me = meFixture({ role: "receptionist" }).data;

    expect(navigationFor(me).map((item) => item.key)).toEqual(["agenda"]);
  });

  it("el dueño de la organización ve el resumen (conteos) pero no la agenda", () => {
    const me = meFixture({ role: "org_owner" }).data;

    expect(navigationFor(me).map((item) => item.key)).toEqual(["summary"]);
  });

  it("un gerente de empresa ve ambos", () => {
    const me = meFixture({ role: "company_manager" }).data;

    expect(navigationFor(me).map((item) => item.key)).toEqual(["agenda", "summary"]);
  });

  it("exige que el backend también ofrezca el ítem (navigation de /me)", () => {
    const me = meFixture({ role: "receptionist" }).data;
    const withoutServerNav = { ...me, navigation: [] };

    expect(navigationFor(withoutServerNav)).toEqual([]);
  });

  it("cada ítem trae su ruta y la clave de i18n de su etiqueta", () => {
    const [agenda] = navigationFor(meFixture({ role: "receptionist" }).data);

    expect(agenda).toMatchObject({ path: "/agenda", labelKey: "nav.agenda" });
  });
});
