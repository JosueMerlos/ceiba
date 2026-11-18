import { usePublicBrandingQuery } from "@ceiba/api-client";
import { fromBranding } from "@ceiba/branding";
import { useApplyBranding } from "@ceiba/branding/react";
import type { ReactNode } from "react";
import { useMe } from "../me/me-provider";

/**
 * Themes the panel with the context company's brand. It reads the PUBLIC endpoint (the same answer, and cache entry,
 * the public booking page uses) so the panel needs no permission to look like the company it works for.
 */
export function BrandingProvider({ children }: { children: ReactNode }) {
  const slug = useMe().context.company?.slug;
  const branding = usePublicBrandingQuery(slug).data?.data;

  useApplyBranding(branding ? fromBranding(branding) : null, branding?.assets.favicon?.icon32);

  return children;
}
