import { createI18n, I18nextProvider, translator, useTranslation } from "@ceiba/i18n";
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { lazyPage } from "./lazy-page";

// Uses a module key through the startup namespace: only the route's registration can load "appointments" in time.
function AgendaTitle() {
  const { t } = useTranslation("common");
  return <h1>{translator(t)("appointments:agenda.viewLabel")}</h1>;
}

describe("lazyPage", () => {
  it("carga los namespaces de la ruta antes de pintar la página (sin claves crudas)", async () => {
    const i18n = await createI18n({ onMissingKey: "throw" });
    expect(i18n.hasResourceBundle("es-NI", "appointments")).toBe(false);

    render(
      <I18nextProvider i18n={i18n}>
        {lazyPage(async () => ({ AgendaTitle }), "AgendaTitle", ["appointments"])}
      </I18nextProvider>,
    );

    expect(await screen.findByRole("heading", { name: "Vista de la agenda" })).toBeTruthy();
    expect(i18n.hasResourceBundle("es-NI", "appointments")).toBe(true);
  });
});
