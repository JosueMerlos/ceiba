import { isHexColor } from "./contrast";
import type { BrandVars, Surfaces } from "./resolve";

/** The closed list of properties branding may write; anything else is ignored. */
export const BRAND_VARS = [
  "--brand-primary",
  "--brand-primary-foreground",
  "--brand-secondary",
  "--brand-secondary-foreground",
  "--brand-accent",
  "--brand-accent-foreground",
  "--brand-font",
  "--ring",
  "--sidebar-ring",
] as const;

const MANAGED = new Set<string>(BRAND_VARS);

const FALLBACK_BACKGROUND = "#FFFFFF";
// Matches --sidebar (kapok-50); test/surfaces-sync.test.ts fails if the token drifts from it.
const FALLBACK_SIDEBAR = "#F2F4EF";

/** Writes the vars and drops any managed one the new brand no longer sets. Other inline styles are untouched. */
export function applyBranding(target: HTMLElement, vars: BrandVars): void {
  for (const key of BRAND_VARS) {
    const value = vars[key];
    if (value === undefined) target.style.removeProperty(key);
    else target.style.setProperty(key, value);
  }
}

export function clearBranding(target: HTMLElement): void {
  for (const key of MANAGED) target.style.removeProperty(key);
}

/** Resolved `--background` and `--sidebar`: what the primary color has to stay visible against. */
export function readSurfaces(root: HTMLElement): Surfaces {
  const style = getComputedStyle(root);
  const read = (name: string, fallback: string) => {
    const value = style.getPropertyValue(name).trim();
    return isHexColor(value) ? value : fallback;
  };
  return {
    background: read("--background", FALLBACK_BACKGROUND),
    sidebar: read("--sidebar", FALLBACK_SIDEBAR),
  };
}
