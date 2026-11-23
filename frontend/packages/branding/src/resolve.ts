import { contrastRatio, isHexColor } from "./contrast";
import { FONT_FAMILIES, type FontChoice } from "./fonts";

/** Text color kapok-900 from the platform palette; the hex must match tokens.css (the palette is the source). */
export const DARK_FOREGROUND_HEX = "#17211C";
const WHITE_HEX = "#FFFFFF";
const DARK_FOREGROUND = "var(--palette-kapok-900)";
const LIGHT_FOREGROUND = "var(--palette-kapok-0)";
const RING_FALLBACK = "var(--palette-canopy-500)";

const MIN_TEXT_CONTRAST = 4.5;
const MIN_UI_CONTRAST = 3;

export interface BrandingInput {
  primaryColor: string | null;
  secondaryColor: string | null;
  accentColor: string | null;
  fontChoice: FontChoice | null;
}

/** The surfaces a primary color must stay visible against (focus ring, WCAG 1.4.11). */
export interface Surfaces {
  background: string;
  sidebar: string;
}

export type BrandVars = Record<string, string>;
export type BrandRole = "primary" | "secondary" | "accent";

export interface BrandNotices {
  /** Roles whose text was switched away from the platform default so it stays readable. */
  darkText: BrandRole[];
  /** The primary is too faint for a focus ring against a surface: the ring uses the palette instead. */
  ringFallback: boolean;
  /** Roles whose color admits no readable text at all: the platform's pair is kept instead. */
  unreadable: BrandRole[];
}

// What each role's text is on the platform palette: only the primary is light text on a dark fill.
const DEFAULT_TEXT_IS_DARK: Record<BrandRole, boolean> = {
  primary: false,
  secondary: true,
  accent: true,
};

const COLOR_FIELDS = {
  primary: "primaryColor",
  secondary: "secondaryColor",
  accent: "accentColor",
} as const satisfies Record<BrandRole, keyof BrandingInput>;

function pickForeground(color: string): "dark" | "light" | null {
  const onWhite = contrastRatio(color, WHITE_HEX);
  const onDark = contrastRatio(color, DARK_FOREGROUND_HEX);
  if (Math.max(onWhite, onDark) < MIN_TEXT_CONTRAST) return null;
  return onDark > onWhite ? "dark" : "light";
}

/** Same as `resolveBrandVars`, plus what the user should be told about automatic corrections. */
export function analyzeBranding(
  input: BrandingInput,
  surfaces: Surfaces,
): { vars: BrandVars; notices: BrandNotices } {
  const vars: BrandVars = {};
  const notices: BrandNotices = { darkText: [], ringFallback: false, unreadable: [] };

  for (const role of Object.keys(COLOR_FIELDS) as BrandRole[]) {
    const color = input[COLOR_FIELDS[role]];
    if (color === null || !isHexColor(color)) continue;

    // Without a readable text color the pair is omitted: the platform's default is kept for both.
    const foreground = pickForeground(color);
    if (foreground === null) {
      notices.unreadable.push(role);
      continue;
    }

    vars[`--brand-${role}`] = color;
    vars[`--brand-${role}-foreground`] = foreground === "dark" ? DARK_FOREGROUND : LIGHT_FOREGROUND;
    if ((foreground === "dark") !== DEFAULT_TEXT_IS_DARK[role]) notices.darkText.push(role);
    if (role === "primary" && !hasRingContrast(color, surfaces)) {
      vars["--ring"] = RING_FALLBACK;
      vars["--sidebar-ring"] = RING_FALLBACK;
      notices.ringFallback = true;
    }
  }

  if (input.fontChoice) vars["--brand-font"] = FONT_FAMILIES[input.fontChoice];
  return { vars, notices };
}

function hasRingContrast(primary: string, { background, sidebar }: Surfaces): boolean {
  return (
    contrastRatio(primary, background) >= MIN_UI_CONTRAST &&
    contrastRatio(primary, sidebar) >= MIN_UI_CONTRAST
  );
}

/** CSS variables to write for a company's brand. A null color emits nothing: the platform palette shows through. */
export function resolveBrandVars(input: BrandingInput, surfaces: Surfaces): BrandVars {
  return analyzeBranding(input, surfaces).vars;
}
