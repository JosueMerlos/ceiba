import { isHexColor, type BrandingInput, type FontChoice } from "@ceiba/branding";
import type { Branding, BrandingChanges, BrandingFile } from "@ceiba/api-client";

// A Record, not a list: a new image kind in the contract fails to compile here until it is handled.
const FILE_KINDS: Record<BrandingFile, true> = { logo: true, banner: true, favicon: true };
export const FILE_FIELDS = Object.keys(FILE_KINDS) as BrandingFile[];
export const COLOR_FIELDS = ["primaryColor", "secondaryColor", "accentColor"] as const;
export type ColorField = (typeof COLOR_FIELDS)[number];

export interface BrandingFormValues {
  brandName: string;
  tagline: string;
  primaryColor: string;
  secondaryColor: string;
  accentColor: string;
  /** "" = the platform's own face (Figtree). */
  fontChoice: FontChoice | "";
  // Files live outside the form state (see use-branding-files); the keys exist so field errors can attach to them.
  logo: null;
  banner: null;
  favicon: null;
}

/** API field name -> form field name (only the ones that differ). */
const FORM_FIELD: Record<string, keyof BrandingFormValues> = {
  brand_name: "brandName",
  tagline: "tagline",
  primary_color: "primaryColor",
  secondary_color: "secondaryColor",
  accent_color: "accentColor",
  font_choice: "fontChoice",
  logo: "logo",
  banner: "banner",
  favicon: "favicon",
};

export const formFieldFor = (apiField: string): keyof BrandingFormValues | undefined =>
  FORM_FIELD[apiField];

export function toFormValues(branding: Branding): BrandingFormValues {
  return {
    brandName: branding.brand_name ?? "",
    tagline: branding.tagline ?? "",
    primaryColor: branding.primary_color ?? "",
    secondaryColor: branding.secondary_color ?? "",
    accentColor: branding.accent_color ?? "",
    fontChoice: branding.font_choice === "figtree" ? "" : (branding.font_choice ?? ""),
    logo: null,
    banner: null,
    favicon: null,
  };
}

/** What the live preview resolves colors from: an empty or half-typed color counts as "not set yet". */
export function toBrandingInput(values: BrandingFormValues): BrandingInput {
  const color = (value: string) => (isHexColor(value) ? value : null);
  return {
    primaryColor: color(values.primaryColor),
    secondaryColor: color(values.secondaryColor),
    accentColor: color(values.accentColor),
    fontChoice: values.fontChoice === "" ? null : values.fontChoice,
  };
}

/** Empty or valid #RRGGBB: an empty color is allowed (it returns to the platform palette). */
export const isValidColorInput = (value: string): boolean => value === "" || isHexColor(value);

export function toChanges(
  values: BrandingFormValues,
  files: Partial<Record<BrandingFile, File>>,
  removed: readonly BrandingFile[],
): BrandingChanges {
  return {
    text: {
      brand_name: values.brandName.trim(),
      tagline: values.tagline.trim(),
      primary_color: values.primaryColor,
      secondary_color: values.secondaryColor,
      accent_color: values.accentColor,
      font_choice: values.fontChoice,
    },
    files,
    remove: removed.filter((name) => !(name in files)),
  };
}

/** The variant shown as a thumbnail for each kind (a variant, never the original). */
const THUMBNAIL_VARIANT: {
  [K in BrandingFile]: (asset: Branding["assets"][K]) => string | undefined;
} = {
  logo: (asset) => asset?.x1,
  banner: (asset) => asset?.standard,
  favicon: (asset) => asset?.icon32,
};

/** Saved URL of each image used as a thumbnail. */
export function savedAssetUrl<K extends BrandingFile>(branding: Branding, name: K): string | null {
  return THUMBNAIL_VARIANT[name](branding.assets[name]) ?? null;
}
