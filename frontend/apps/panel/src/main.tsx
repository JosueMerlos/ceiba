import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/app";
import { createApp } from "./app/create-app";
import "./styles.css";

// Sentry se carga aparte (chunk propio) y solo si hay DSN: no pesa en el arranque. Los errores anteriores a su carga
// (milisegundos) no se reportan; es el precio de no cargar ~100 KiB antes de pintar el login.
if (import.meta.env.VITE_SENTRY_DSN) void import("./sentry").then(({ initSentry }) => initSentry());

const app = await createApp();
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App app={app} />
  </StrictMode>,
);
