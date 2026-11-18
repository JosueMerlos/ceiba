export const FONT_CHOICES = ["figtree", "lora", "nunito"] as const;
export type FontChoice = (typeof FONT_CHOICES)[number];

/** font-family written to --brand-font. Figtree is the platform's own body face, so it needs no extra loading. */
export const FONT_FAMILIES: Record<FontChoice, string> = {
  figtree: "var(--palette-font-body)",
  lora: '"Lora Variable", ui-serif, Georgia, serif',
  nunito: '"Nunito Variable", ui-sans-serif, system-ui, sans-serif',
};
