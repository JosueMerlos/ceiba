import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// The browser connects through the proxy (public port), not Vite's: the HMR websocket must point at that port to go
// through the proxy.
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);

export default defineConfig({
  base: "/c/",
  plugins: [react(), tailwindcss()],
  server: {
    host: true,
    port: 5174,
    strictPort: true,
    hmr: { clientPort: publicPort },
  },
  build: { manifest: true },
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.{ts,tsx}"],
    testTimeout: 15_000,
  },
});
