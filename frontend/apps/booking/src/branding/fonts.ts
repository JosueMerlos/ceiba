import type { FontChoice } from "@ceiba/branding";

// Each font is a separate on-demand chunk: a company that keeps Figtree (the platform's own face) downloads nothing.
const loaders: Partial<Record<FontChoice, () => Promise<unknown>>> = {
  lora: () => import("@fontsource-variable/lora"),
  nunito: () => import("@fontsource-variable/nunito"),
};

/** Loads the face's CSS. A failure (offline) leaves the fallback family in place, so it is not an error to show. */
export function loadBrandFont(choice: FontChoice): Promise<void> {
  const load = loaders[choice];
  return load
    ? load().then(
        () => undefined,
        () => undefined,
      )
    : Promise.resolve();
}
