import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { App } from "./App";

test("muestra el placeholder del panel", () => {
  render(<App />);

  expect(screen.getByRole("heading", { name: /panel/i })).toBeTruthy();
});
