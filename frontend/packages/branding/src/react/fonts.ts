import type { FontChoice } from "../fonts";

// Each font is a separate on-demand chunk: a company that keeps Figtree (the platform's own face) downloads nothing.
const loaders: Partial<Record<FontChoice, () => Promise<unknown>>> = {
  lora: () => import("@fontsource-variable/lora"),
  nunito: () => import("@fontsource-variable/nunito"),
};

const requested = new Map<FontChoice, Promise<void>>();

/** Loads the face's CSS once. A failure (offline) leaves the fallback family in place, so it is not an error to show. */
export function loadBrandFont(choice: FontChoice): Promise<void> {
  const load = loaders[choice];
  if (!load) return Promise.resolve();
  let pending = requested.get(choice);
  if (!pending) {
    pending = load().then(
      () => undefined,
      () => {
        requested.delete(choice);
      },
    );
    requested.set(choice, pending);
  }
  return pending;
}
