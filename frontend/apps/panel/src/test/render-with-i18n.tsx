import { createI18n, I18nextProvider } from "@ceiba/i18n";
import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactElement } from "react";

/**
 * Mounts one presentational component with the WHOLE real es-NI catalog (a missing key throws). No router, no API: the
 * component is mounted without its route, so it cannot rely on the route loading its namespace.
 */
export async function renderWithI18n(ui: ReactElement) {
  const i18n = await createI18n({ onMissingKey: "throw", preload: "all" });
  const user = userEvent.setup();
  const view = render(<I18nextProvider i18n={i18n}>{ui}</I18nextProvider>);
  return { user, ...view };
}
