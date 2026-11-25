import type { AgendaDensity } from "./types";

/** The day view's time slot: every width below is per slot of this length. */
export const SLOT_MINUTES = 30;

/** Pixels per slot. The row heights that go with each density live in the agenda's stylesheet. */
export const SLOT_WIDTH: Record<AgendaDensity, number> = {
  comfortable: 88,
  compact: 64,
};

// The gap the library leaves around a card, so neighbors never touch.
const CARD_GUTTER_PX = 4;
const FULL_FROM_PX = 96;
const NAME_FROM_PX = 56;

export type CardTier = "full" | "name" | "initials";

/** The width an appointment of this length takes on screen, in pixels. */
export const cardWidth = (minutes: number, density: AgendaDensity) =>
  (minutes * SLOT_WIDTH[density]) / SLOT_MINUTES - CARD_GUTTER_PX;

/** What a card can show is decided by its width, so the same appointment changes with the density. */
export function cardTier(minutes: number, density: AgendaDensity): CardTier {
  const width = cardWidth(minutes, density);
  if (width >= FULL_FROM_PX) return "full";
  if (width >= NAME_FROM_PX) return "name";
  return "initials";
}
