import { cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./server";

beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
  document.documentElement.removeAttribute("style");
  document.head.querySelectorAll("link[rel~='icon']").forEach((link) => link.remove());
  window.history.pushState({}, "", "/");
});
afterAll(() => server.close());
