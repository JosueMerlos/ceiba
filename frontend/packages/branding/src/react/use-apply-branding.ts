import { useEffect } from "react";
import { applyBranding, clearBranding, readSurfaces } from "../apply";
import { resolveBrandVars, type BrandingInput } from "../resolve";
import { loadBrandFont } from "./fonts";

/**
 * Themes the document with a brand and undoes it on change or unmount. `null` means "nothing to apply yet".
 * The input is compared by value, so callers may build it on every render.
 */
export function useApplyBranding(input: BrandingInput | null, faviconHref?: string) {
  const present = input !== null;
  const primaryColor = input?.primaryColor;
  const secondaryColor = input?.secondaryColor;
  const accentColor = input?.accentColor;
  const fontChoice = input?.fontChoice;

  useEffect(() => {
    if (!present) return;
    const root = document.documentElement;
    const resolved = {
      primaryColor: primaryColor ?? null,
      secondaryColor: secondaryColor ?? null,
      accentColor: accentColor ?? null,
      fontChoice: fontChoice ?? null,
    };
    applyBranding(root, resolveBrandVars(resolved, readSurfaces(root)));
    if (resolved.fontChoice) void loadBrandFont(resolved.fontChoice);
    // Switching company (or losing the brand) must not leave the previous one's colors behind.
    return () => clearBranding(root);
  }, [present, primaryColor, secondaryColor, accentColor, fontChoice]);

  useFavicon(faviconHref);
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
