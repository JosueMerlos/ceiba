import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The browser connects through the proxy (public port), not Vite's: the HMR websocket must point at that port to go
// through the proxy.
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);

export default defineConfig({
  base: "/",
  plugins: [react(), tailwindcss()],
  // Under Vitest packages resolve for Node, and the calendar's Svelte runtime only mounts in its browser build.
  ...(process.env.VITEST ? { resolve: { conditions: ["browser"] } } : {}),
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
        // One chunk per business module: modules/<key>/... -> assets/module-<key>-<hash>.js
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
    server: { deps: { inline: [/@event-calendar/, /svelte/] } },
    // The production build (app/build.test.ts) takes a few seconds.
    testTimeout: 15_000,
  },
});
