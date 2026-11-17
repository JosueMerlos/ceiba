import {
  applyBranding,
  clearBranding,
  isHexColor,
  readSurfaces,
  resolveBrandVars,
  type FontChoice,
} from "@ceiba/branding";
import { useEffect, useState } from "react";
import { loadBrandFont } from "./fonts";

interface Asset {
  [variant: string]: string;
}

export interface PublicBranding {
  brand_name: string | null;
  tagline: string | null;
  primary_color: string | null;
  secondary_color: string | null;
  accent_color: string | null;
  font_choice: FontChoice | null;
  assets: { logo: Asset | null; banner: Asset | null; favicon: Asset | null };
}

export type BrandingState =
  { status: "loading" } | { status: "not-found" } | { status: "ready"; branding: PublicBranding };

/** The company slug of `/c/:slug`, or null on the bare entry (no company chosen). */
export function slugFromPath(pathname: string): string | null {
  const match = /^\/c\/([^/]+)/.exec(pathname);
  return match ? decodeURIComponent(match[1]!) : null;
}

const color = (value: string | null) => (value !== null && isHexColor(value) ? value : null);

/**
 * Fetches the company's public brand and themes the document with it. A plain fetch (not TanStack Query) keeps the
 * booking entry small. An unknown company is "not-found"; any other failure falls back to the platform palette.
 */
export function usePublicBranding(slug: string | null): BrandingState {
  const [state, setState] = useState<BrandingState>({ status: "loading" });

  useEffect(() => {
    if (!slug) return;
    const controller = new AbortController();
    fetch(`/api/public/v1/c/${encodeURIComponent(slug)}/branding`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (response.status === 404) return setState({ status: "not-found" });
        if (!response.ok) throw new Error(String(response.status));
        const { data } = (await response.json()) as { data: PublicBranding };
        setState({ status: "ready", branding: data });
      })
      .catch((error: unknown) => {
        if ((error as Error).name !== "AbortError") {
          setState({ status: "ready", branding: EMPTY_BRANDING });
        }
      });
    return () => controller.abort();
  }, [slug]);

  const branding = state.status === "ready" ? state.branding : null;

  useEffect(() => {
    if (!branding) return;
    const root = document.documentElement;
    applyBranding(
      root,
      resolveBrandVars(
        {
          primaryColor: color(branding.primary_color),
          secondaryColor: color(branding.secondary_color),
          accentColor: color(branding.accent_color),
          fontChoice: branding.font_choice,
        },
        readSurfaces(root),
      ),
    );
    if (branding.font_choice) void loadBrandFont(branding.font_choice);
    return () => clearBranding(root);
  }, [branding]);

  useFavicon(branding?.assets.favicon?.icon32);

  return state;
}

const EMPTY_BRANDING: PublicBranding = {
  brand_name: null,
  tagline: null,
  primary_color: null,
  secondary_color: null,
  accent_color: null,
  font_choice: null,
  assets: { logo: null, banner: null, favicon: null },
};

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
