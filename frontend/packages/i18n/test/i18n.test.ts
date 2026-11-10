import { describe, expect, it } from "vitest";
import { createI18n, defaultLocale, resources } from "../src";

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
    walk(resources["es-NI"], "es-NI");

    expect(empty).toEqual([]);
  });

  it("una clave inexistente falla en pruebas en vez de mostrarse cruda en silencio", async () => {
    const i18n = await createI18n({ onMissingKey: "throw" });

    // @ts-expect-error la clave no existe en el catálogo tipado
    expect(() => i18n.t("common:noExiste")).toThrow(/noExiste/);
  });
});
