import { defineConfig, devices } from "@playwright/test";

// E2E contra el entorno de Compose (proxy en el puerto público). Los datos son los seeds de demo (backend/db/seeds.rb).
// Los tests son de solo lectura sobre los datos (no crean ni borran nada) y no comparten sesión: cada uno inicia la suya.
export default defineConfig({
  testDir: "./tests",
  outputDir: "./test-results",
  fullyParallel: false,
  workers: 1,
  // Sin reintentos por defecto (la imagen fija CI=true y eso no debe esconder tests inestables en local).
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
