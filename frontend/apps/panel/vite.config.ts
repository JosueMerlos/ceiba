import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// El navegador entra por el proxy (puerto público), no por el de Vite: el websocket
// de HMR debe apuntar a ese puerto para atravesar el proxy (ADR-0013).
const publicPort = Number(process.env.PUBLIC_PORT ?? 8080);

export default defineConfig({
  base: "/",
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    hmr: { clientPort: publicPort },
  },
  test: {
    environment: "jsdom",
  },
});
