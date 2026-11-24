import { cleanup, configure } from "@testing-library/react";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./server";

// Pages are lazy routes: the first test of a file to mount one also waits for Vitest to compile that chunk (the agenda's
// chunk pulls in the whole calendar), which on a busy CI runner takes longer than the 1 s default of `findBy*`/`waitFor`. Any
// test can run first, so the margin is global; it only lengthens how long a test that already fails takes to report.
configure({ asyncUtilTimeout: 5_000 });

beforeAll(() => server.listen({ onUnhandledFrame: "error" }));
afterEach(() => {
  cleanup();
  server.resetHandlers();
});
afterAll(() => server.close());

// Build tests (node environment) have no DOM.
if (typeof window !== "undefined") {
  // jsdom does not implement these APIs, which Radix uses for focus and pointer handling.
  Element.prototype.hasPointerCapture ??= () => false;
  Element.prototype.setPointerCapture ??= () => {};
  Element.prototype.releasePointerCapture ??= () => {};
  Element.prototype.scrollIntoView ??= () => {};
  // The agenda's calendar asks what is under the pointer; jsdom has no layout to answer with.
  Document.prototype.elementsFromPoint ??= () => [];
  globalThis.ResizeObserver ??= class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
  window.matchMedia ??= ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener() {},
    removeEventListener() {},
    addListener() {},
    removeListener() {},
    dispatchEvent: () => false,
  })) as typeof window.matchMedia;
}
