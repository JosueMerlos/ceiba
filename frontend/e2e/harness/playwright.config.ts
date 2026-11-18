import { defineConfig } from "@playwright/test";
import base from "../playwright.config";

// UI QA smokes (ticket evidence). Kept out of `make e2e` (testDir ./tests): run with `pnpm exec playwright test -c harness/playwright.config.ts`.
export default defineConfig({
  ...base,
  testDir: ".",
  testMatch: /.*\.spec\.ts/,
  outputDir: "../test-results/harness",
  reporter: [["list"]],
});
