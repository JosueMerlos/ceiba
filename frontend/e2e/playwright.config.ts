import { defineConfig, devices } from "@playwright/test";

// E2E against the Compose environment (proxy on the public port). Data comes from the demo seeds (backend/db/seeds.rb).
// Tests are read-only on the data (they create and delete nothing) and share no session: each one logs in on its own.
export default defineConfig({
  testDir: "./tests",
  outputDir: "./test-results",
  fullyParallel: false,
  workers: 1,
  // No retries by default (the image sets CI=true and that must not hide flaky tests locally).
  retries: Number(process.env.E2E_RETRIES ?? 0),
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:8080",
    locale: "es-NI",
    timezoneId: "America/Managua",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
