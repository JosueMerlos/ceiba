import { useTranslation } from "@ceiba/i18n";
import { CeibaMark } from "@ceiba/ui";
import { BrandHeader } from "./branding/brand-header";
import { slugFromPath, usePublicBranding } from "./branding/use-public-branding";

// Shares tokens and primitives with the panel but NOT the full design system: only what is used is imported
// (tree-shaking) to stay within the bundle budget.
export function App() {
  const slug = slugFromPath(window.location.pathname);
  return slug ? <CompanyPage slug={slug} /> : <Stub />;
}

function CompanyPage({ slug }: { slug: string }) {
  const { t } = useTranslation("booking");
  const state = usePublicBranding(slug);

  if (state.status === "loading") {
    return <main aria-busy="true" className="min-h-svh" />;
  }
  if (state.status === "not-found") {
    return (
      <main className="mx-auto grid min-h-svh max-w-md place-content-center gap-4 px-4 text-center">
        <CeibaMark className="mx-auto size-14" />
        <h1 className="font-display text-3xl font-semibold">{t("notFound.title")}</h1>
        <p className="text-muted-foreground">{t("notFound.description")}</p>
      </main>
    );
  }
  return (
    <main className="min-h-svh">
      <BrandHeader branding={state.branding} />
    </main>
  );
}

function Stub() {
  const { t } = useTranslation("booking");
  return (
    <main className="mx-auto grid min-h-svh max-w-md place-content-center gap-4 px-4 text-center">
      <CeibaMark className="mx-auto size-14" />
      <h1 className="font-display text-3xl font-semibold">{t("title")}</h1>
      <p className="text-muted-foreground">{t("description")}</p>
    </main>
  );
}
