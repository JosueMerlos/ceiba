import { fromBranding, type FontChoice } from "@ceiba/branding";
import { useApplyBranding } from "@ceiba/branding/react";
import { useEffect, useState } from "react";

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
  useApplyBranding(branding ? fromBranding(branding) : null, branding?.assets.favicon?.icon32);

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
