import { createI18n, I18nextProvider } from "@ceiba/i18n";
import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { App } from "./App";

test("muestra la página de reserva en es-NI con el nombre del producto", async () => {
  const i18n = await createI18n();
  render(
    <I18nextProvider i18n={i18n}>
      <App />
    </I18nextProvider>,
  );

  expect(screen.getByRole("heading", { name: "Reserve su cita" })).toBeTruthy();
  expect(screen.getByRole("main")).toBeTruthy();
});
