import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/app";
import { createApp } from "./app/create-app";
import "./styles.css";

// Sentry loads separately (own chunk) and only with a DSN, so it does not weigh on startup. Errors before it loads
// (milliseconds) go unreported; that is the price of not loading ~100 KiB before painting the login.
if (import.meta.env.VITE_SENTRY_DSN) void import("./sentry").then(({ initSentry }) => initSentry());

const app = await createApp();
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App app={app} />
  </StrictMode>,
);
