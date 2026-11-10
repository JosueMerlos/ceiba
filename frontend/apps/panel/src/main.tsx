import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/app";
import { createApp } from "./app/create-app";
import { initSentry } from "./sentry";
import "./styles.css";

initSentry();

const app = await createApp();
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App app={app} />
  </StrictMode>,
);
