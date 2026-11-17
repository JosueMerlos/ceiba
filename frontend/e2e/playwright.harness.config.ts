import { defineConfig, devices } from "@playwright/test";

// UI QA smoke for a milestone (not part of `make e2e`): records video and screenshots as PR evidence.
export default defineConfig({
  testDir: "./harness",
  outputDir: "./test-results/harness",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:8080",
    locale: "es-NI",
    timezoneId: "America/Managua",
    video: "on",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
