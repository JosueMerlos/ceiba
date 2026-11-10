import { useTranslation } from "@ceiba/i18n";
import { CeibaMark } from "@ceiba/ui";

// Estructura base de la reserva pública (ADR-0015): sin funcionalidad todavía. Comparte tokens y primitivas con el
// panel, pero NO el design system completo: solo se importa lo que se usa (tree-shaking), por el presupuesto de bundle.
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
