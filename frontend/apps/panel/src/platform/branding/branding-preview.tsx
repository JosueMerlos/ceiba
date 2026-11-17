import { applyBranding, type BrandVars } from "@ceiba/branding";
import { useTranslation } from "@ceiba/i18n";
import { Button, Input, NavItem } from "@ceiba/ui";
import { useLayoutEffect, useRef } from "react";

interface BrandingPreviewProps {
  vars: BrandVars;
  name: string;
  tagline: string;
  logoUrl: string | null;
  bannerUrl: string | null;
}

/**
 * Live sample of the brand. It is a `[data-brand-scope]` container: the semantic tokens are declared again inside it, so
 * the --brand-* written here (and only here) restyle the sample while the rest of the panel keeps the saved brand.
 */
export function BrandingPreview({ vars, name, tagline, logoUrl, bannerUrl }: BrandingPreviewProps) {
  const { t } = useTranslation("branding");
  const scope = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (scope.current) applyBranding(scope.current, vars);
  }, [vars]);

  return (
    <section aria-label={t("preview.label")}>
      {/* A sample, not controls: inert keeps its buttons and links out of the tab order and the accessibility tree. */}
      <div
        ref={scope}
        data-brand-scope
        inert
        className="overflow-hidden rounded-xl border bg-background font-sans text-foreground"
      >
        <div className="h-28 bg-secondary md:h-36">
          {bannerUrl ? <img src={bannerUrl} alt="" className="size-full object-cover" /> : null}
        </div>

        <div className="flex items-center gap-3 px-5 pt-4">
          {logoUrl ? (
            <img
              src={logoUrl}
              alt={t("preview.logoAlt", { name })}
              className="h-12 w-auto max-w-32 object-contain"
            />
          ) : (
            <span
              aria-hidden="true"
              className="grid size-12 place-items-center rounded-lg bg-primary font-display text-lg font-semibold text-primary-foreground"
            >
              {name.trim().charAt(0).toUpperCase()}
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate font-display text-xl font-semibold">{name}</p>
            <p className="truncate text-sm text-muted-foreground">
              {tagline || t("preview.fallbackTagline")}
            </p>
          </div>
        </div>

        <div className="grid gap-5 p-5 md:grid-cols-[11rem_minmax(0,1fr)]">
          <nav className="grid content-start gap-1">
            <NavItem asChild>
              <div aria-current="page">{t("preview.menuItem")}</div>
            </NavItem>
            <NavItem asChild>
              <div>{t("preview.menuOther")}</div>
            </NavItem>
          </nav>
          <div className="grid content-start gap-4">
            <div className="flex flex-wrap items-center gap-2">
              <Button>{t("preview.cta")}</Button>
              <Button variant="secondary">{t("preview.secondary")}</Button>
              <span className="rounded-full bg-highlight px-2.5 py-1 text-xs font-semibold text-highlight-foreground">
                {t("preview.badge")}
              </span>
            </div>
            <p>
              <span className="text-primary underline underline-offset-4">{t("preview.link")}</span>
            </p>
            {/* Shown in its focused state on purpose: it is where a too-faint primary would become invisible. */}
            <div className="grid gap-1.5">
              <span className="text-sm font-medium">{t("preview.inputLabel")}</span>
              <Input
                readOnly
                tabIndex={-1}
                defaultValue={t("preview.inputValue")}
                className="border-ring ring-3 ring-ring/30"
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
