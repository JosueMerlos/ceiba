import { useTranslation } from "@ceiba/i18n";
import { CeibaMark } from "@ceiba/ui";
import type { PublicBranding } from "./use-public-branding";

/** Banner, logo, name and tagline of the company; without any of them, the platform mark. */
export function BrandHeader({ branding }: { branding: PublicBranding }) {
  const { t } = useTranslation("booking");
  const { logo, banner } = branding.assets;
  const name = branding.brand_name;
  const hasIdentity = !!(logo || banner || name || branding.tagline);

  if (!hasIdentity) {
    return (
      <header className="grid justify-items-center gap-4 px-4 py-12 text-center">
        <CeibaMark className="size-14" />
        <h1 className="font-display text-3xl font-semibold">{t("title")}</h1>
        <p className="text-muted-foreground">{t("description")}</p>
      </header>
    );
  }

  return (
    <header className="border-b border-border">
      {banner?.standard && (
        <picture>
          {banner.wide && <source media="(min-width: 768px)" srcSet={banner.wide} />}
          <img
            src={banner.standard}
            alt=""
            className="block aspect-[4/3] w-full object-cover md:aspect-[16/9]"
          />
        </picture>
      )}
      <div className="mx-auto flex max-w-2xl items-center gap-4 px-4 py-6">
        {logo?.x1 && (
          <img
            src={logo.x1}
            srcSet={logo.x2 ? `${logo.x1} 1x, ${logo.x2} 2x` : undefined}
            alt={name ? t("logoAlt", { name }) : t("logoAltGeneric")}
            className="h-16 w-auto max-w-40 shrink-0 object-contain"
          />
        )}
        <div className="grid gap-1">
          {name && <h1 className="font-display text-2xl font-semibold">{name}</h1>}
          {branding.tagline && <p className="text-muted-foreground">{branding.tagline}</p>}
        </div>
      </div>
    </header>
  );
}
