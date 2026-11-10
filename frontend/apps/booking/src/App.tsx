import { useTranslation } from "@ceiba/i18n";
import { CeibaMark } from "@ceiba/ui";

// Shares tokens and primitives with the panel but NOT the full design system: only what is used is imported
// (tree-shaking) to stay within the bundle budget.
export function App() {
  const { t } = useTranslation(["booking", "common"]);
  return (
    <main className="mx-auto grid min-h-svh max-w-md place-content-center gap-4 px-4 text-center">
      <CeibaMark className="mx-auto size-14" />
      <h1 className="font-display text-3xl font-semibold">{t("booking:title")}</h1>
      <p className="text-muted-foreground">{t("booking:description")}</p>
    </main>
  );
}
