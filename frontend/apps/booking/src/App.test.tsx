import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { App } from "./App";

test("muestra el placeholder de la reserva pública", () => {
  render(<App />);

  expect(screen.getByRole("heading", { name: /reserva/i })).toBeTruthy();
});
