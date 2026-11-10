import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// El navegador entra por el proxy (puerto público), no por el de Vite: el websocket
// de HMR debe apuntar a ese puerto para atravesar el proxy (ADR-0013).
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);

export default defineConfig({
  base: "/",
  plugins: [react(), tailwindcss()],
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    hmr: { clientPort: publicPort },
  },
  build: {
    manifest: true,
    rollupOptions: {
      output: {
        // Un chunk por módulo de negocio: modules/<clave>/... -> assets/module-<clave>-<hash>.js
        chunkFileNames: (chunk) => {
          const key = /\/modules\/([^/]+)\//.exec(chunk.facadeModuleId ?? "")?.[1];
          return key ? `assets/module-${key}-[hash].js` : "assets/[name]-[hash].js";
        },
      },
    },
  },
  test: {
    environment: "jsdom",
    environmentOptions: { jsdom: { url: "http://localhost:8080/" } },
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    // El build de producción (app/build.test.ts) tarda unos segundos.
    testTimeout: 15_000,
  },
});
