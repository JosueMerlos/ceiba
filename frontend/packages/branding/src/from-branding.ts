import { isHexColor } from "./contrast";
import type { FontChoice } from "./fonts";
import type { BrandingInput } from "./resolve";

/** The slice of the public brand that drives theming; the API's `Branding` satisfies it structurally. */
export interface BrandingFields {
  primary_color: string | null;
  secondary_color: string | null;
  accent_color: string | null;
  font_choice: FontChoice | null;
}

const color = (value: string | null) => (value !== null && isHexColor(value) ? value : null);

/** Brand as the API returns it -> theming input. Figtree is the platform's own face, so it counts as "not chosen". */
export function fromBranding(branding: BrandingFields): BrandingInput {
  return {
    primaryColor: color(branding.primary_color),
    secondaryColor: color(branding.secondary_color),
    accentColor: color(branding.accent_color),
    fontChoice: branding.font_choice === "figtree" ? null : branding.font_choice,
  };
}
