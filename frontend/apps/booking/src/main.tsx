import { I18nextProvider } from "@ceiba/i18n";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { createBookingI18n } from "./i18n";
import "./styles.css";

const i18n = await createBookingI18n();
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <I18nextProvider i18n={i18n}>
      <App />
    </I18nextProvider>
  </StrictMode>,
);
