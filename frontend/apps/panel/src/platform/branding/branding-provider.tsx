import { usePublicBrandingQuery } from "@ceiba/api-client";
import { applyBranding, clearBranding, readSurfaces, resolveBrandVars } from "@ceiba/branding";
import { useEffect, type ReactNode } from "react";
import { useMe } from "../me/me-provider";
import { brandingToInput } from "./branding-form";
import { loadBrandFont } from "./fonts";

/**
 * Themes the panel with the context company's brand. It reads the PUBLIC endpoint (the same answer, and cache entry,
 * the public booking page uses) so the panel needs no permission to look like the company it works for.
 */
export function BrandingProvider({ children }: { children: ReactNode }) {
  const slug = useMe().context.company?.slug;
  const branding = usePublicBrandingQuery(slug).data?.data;

  useEffect(() => {
    if (!branding) return;
    const root = document.documentElement;
    applyBranding(root, resolveBrandVars(brandingToInput(branding), readSurfaces(root)));
    if (branding.font_choice) void loadBrandFont(branding.font_choice);
    // Switching company (or losing the brand) must not leave the previous one's colors behind.
    return () => clearBranding(root);
  }, [branding]);

  useFavicon(branding?.assets.favicon?.icon32);

  return children;
}

function useFavicon(href: string | undefined) {
  useEffect(() => {
    if (!href) return;
    const existing = document.head.querySelector<HTMLLinkElement>('link[rel~="icon"]');
    const link = existing ?? Object.assign(document.createElement("link"), { rel: "icon" });
    const previous = { href: link.getAttribute("href"), type: link.getAttribute("type") };
    if (!existing) document.head.append(link);
    link.setAttribute("href", href);
    // The company favicon is always a PNG variant; a leftover type="image/svg+xml" would make the browser ignore it.
    link.setAttribute("type", "image/png");
    return () => {
      if (!existing) return link.remove();
      for (const [attribute, value] of Object.entries(previous)) {
        if (value === null) link.removeAttribute(attribute);
        else link.setAttribute(attribute, value);
      }
    };
  }, [href]);
}
