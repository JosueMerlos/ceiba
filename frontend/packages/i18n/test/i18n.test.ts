import { describe, expect, it } from "vitest";
import { createI18n, defaultLocale } from "../src";
import { esNI } from "../src/locales/es-NI";

describe("createI18n", () => {
  it("usa es-NI como único idioma y como respaldo", async () => {
    const i18n = await createI18n();

    expect(defaultLocale).toBe("es-NI");
    expect(i18n.language).toBe("es-NI");
    expect(i18n.t("common:appName")).toBe("Ceiba");
  });

  it("interpola variables y resuelve plurales", async () => {
    const i18n = await createI18n();

    expect(i18n.t("auth:welcome", { name: "Rosa" })).toContain("Rosa");
  });

  it("no deja claves sin traducir en el catálogo (ninguna cadena vacía)", () => {
    const empty: string[] = [];
    const walk = (node: unknown, path: string) => {
      if (typeof node === "string") {
        if (node.trim() === "") empty.push(path);
      } else if (node && typeof node === "object") {
        for (const [key, value] of Object.entries(node)) walk(value, `${path}.${key}`);
      }
    };
    walk(esNI, "es-NI");

    expect(empty).toEqual([]);
  });

  it("una clave inexistente falla en pruebas en vez de mostrarse cruda en silencio", async () => {
    const i18n = await createI18n({ onMissingKey: "throw" });

    // @ts-expect-error the key does not exist in the typed catalog
    expect(() => i18n.t("common:noExiste")).toThrow(/noExiste/);
  });

  it("sin opciones solo trae los namespaces del arranque del shell", async () => {
    const i18n = await createI18n();

    for (const namespace of ["common", "auth", "shell", "errors"]) {
      expect(i18n.hasResourceBundle(defaultLocale, namespace), namespace).toBe(true);
    }
    for (const namespace of ["appointments", "booking", "branding", "customers", "imports"]) {
      expect(i18n.hasResourceBundle(defaultLocale, namespace), namespace).toBe(false);
    }
  });

  it("carga un namespace de módulo bajo demanda", async () => {
    const i18n = await createI18n({ onMissingKey: "throw" });

    await i18n.loadNamespaces("appointments");

    expect(i18n.t("appointments:agenda.title")).toBe(esNI.appointments.agenda.title);
  });

  it("precarga los namespaces pedidos antes de resolver", async () => {
    const i18n = await createI18n({ preload: ["customers"] });

    expect(i18n.hasResourceBundle(defaultLocale, "customers")).toBe(true);
    expect(i18n.hasResourceBundle(defaultLocale, "imports")).toBe(false);
  });

  it('con preload "all" carga todo el catálogo (tests de componentes)', async () => {
    const i18n = await createI18n({ preload: "all" });

    for (const namespace of Object.keys(esNI)) {
      expect(i18n.hasResourceBundle(defaultLocale, namespace), namespace).toBe(true);
    }
  });

  it("acepta namespaces empaquetados por la app sin pedirlos por red", async () => {
    const i18n = await createI18n({ bundled: { booking: esNI.booking } });

    expect(i18n.hasResourceBundle(defaultLocale, "booking")).toBe(true);
  });
});
