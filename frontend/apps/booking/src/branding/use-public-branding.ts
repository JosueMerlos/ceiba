import type { Branding } from "@ceiba/api-client";
import { fromBranding } from "@ceiba/branding";
import { useApplyBranding } from "@ceiba/branding/react";
import { useEffect, useState } from "react";

export type BrandingState =
  { status: "loading" } | { status: "not-found" } | { status: "ready"; branding: Branding };

/**
 * The company slug of `/c/:slug`, or null on the bare entry (no company chosen). A malformed escape (`%E0%A4`) is kept as
 * written: no company has it as a slug, so the lookup answers "not found" instead of the page crashing.
 */
export function slugFromPath(pathname: string): string | null {
  const match = /^\/c\/([^/]+)/.exec(pathname);
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]!);
  } catch {
    return match[1]!;
  }
}

// The result is tied to the slug it was fetched for, so a different slug (or none) is "loading" at once, never the previous
// company's brand while the new one loads.
type Settled = { slug: string; result: Exclude<BrandingState, { status: "loading" }> };

/**
 * Fetches the company's public brand and themes the document with it. A plain fetch (not TanStack Query) keeps the
 * booking entry small. An unknown company is "not-found"; any other failure falls back to the platform palette.
 */
export function usePublicBranding(slug: string | null): BrandingState {
  const [settled, setSettled] = useState<Settled | null>(null);
  const state: BrandingState =
    slug && settled?.slug === slug ? settled.result : { status: "loading" };

  useEffect(() => {
    if (!slug) return;
    const controller = new AbortController();
    fetch(`/api/public/v1/c/${encodeURIComponent(slug)}/branding`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (response.status === 404) return setSettled({ slug, result: { status: "not-found" } });
        if (!response.ok) throw new Error(String(response.status));
        const { data } = (await response.json()) as { data: Branding };
        setSettled({ slug, result: { status: "ready", branding: data } });
      })
      .catch((error: unknown) => {
        if ((error as Error).name !== "AbortError") {
          setSettled({ slug, result: { status: "ready", branding: EMPTY_BRANDING } });
        }
      });
    return () => controller.abort();
  }, [slug]);

  const branding = state.status === "ready" ? state.branding : null;
  useApplyBranding(branding ? fromBranding(branding) : null, branding?.assets.favicon?.icon32);

  return state;
}

const EMPTY_BRANDING: Branding = {
  brand_name: null,
  tagline: null,
  primary_color: null,
  secondary_color: null,
  accent_color: null,
  font_choice: null,
  assets: { logo: null, banner: null, favicon: null },
};
